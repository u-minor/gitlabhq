class ApplicationController < ActionController::Base
  before_filter :authenticate_user!
  before_filter :reject_blocked!
  before_filter :set_current_user_for_mailer
  before_filter :check_token_auth
  before_filter :set_current_user_for_observers
  before_filter :dev_tools if Rails.env == 'development'

  protect_from_forgery

  helper_method :abilities, :can?

  rescue_from Gitlab::Gitolite::AccessDenied do |exception|
    render "errors/gitolite", layout: "error", status: 500
  end

  rescue_from Encoding::CompatibilityError do |exception|
    render "errors/encoding", layout: "error", status: 500
  end

  rescue_from ActiveRecord::RecordNotFound do |exception|
    render "errors/not_found", layout: "error", status: 404
  end

  layout :layout_by_resource

  protected

  def check_token_auth
    # Redirect to login page if not atom feed
    if params[:private_token].present? && params[:format] != 'atom'
      redirect_to new_user_session_path
    end
  end

  def reject_blocked!
    if current_user && current_user.blocked
      sign_out current_user
      flash[:alert] = "Your account was blocked"
      redirect_to new_user_session_path
    end
  end

  def after_sign_in_path_for resource
    if resource.is_a?(User) && resource.respond_to?(:blocked) && resource.blocked
      sign_out resource
      flash[:alert] = "Your account was blocked"
      new_user_session_path
    else
      super
    end
  end

  def layout_by_resource
    if devise_controller?
      "devise_layout"
    else
      "application"
    end
  end

  def set_current_user_for_mailer
    MailerObserver.current_user = current_user
  end

  def set_current_user_for_observers
    IssueObserver.current_user = current_user
  end

  def abilities
    @abilities ||= Six.new
  end

  def can?(object, action, subject)
    abilities.allowed?(object, action, subject)
  end

  def project
    @project ||= current_user.projects.find_by_code(params[:project_id]) || Project.find_by_code_and_private_flag(params[:project_id], false)
    @project || render_404
  end

  def add_project_abilities
    abilities << Ability
  end

  def authorize_project!(action)
    return access_denied! unless can?(current_user, action, project)
  end

  def authorize_code_access!
    return access_denied! unless can?(current_user, :download_code, project)
  end

  def access_denied!
    render "errors/access_denied", layout: "error", status: 404
  end

  def not_found!
    render "errors/not_found", layout: "error", status: 404
  end

  def git_not_found!
    render "errors/git_not_found", layout: "error", status: 404
  end

  def method_missing(method_sym, *arguments, &block)
    if method_sym.to_s =~ /^authorize_(.*)!$/
      authorize_project!($1.to_sym)
    else
      super
    end
  end

  def render_404
    render file: File.join(Rails.root, "public", "404"), layout: false, status: "404"
  end

  def require_non_empty_project
    redirect_to @project if @project.empty_repo?
  end

  def no_cache_headers
    response.headers["Cache-Control"] = "no-cache, no-store, max-age=0, must-revalidate"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "Fri, 01 Jan 1990 00:00:00 GMT"
  end

  def render_full_content
    @full_content = true
  end

  def dev_tools
    Rack::MiniProfiler.authorize_request
  end
end
