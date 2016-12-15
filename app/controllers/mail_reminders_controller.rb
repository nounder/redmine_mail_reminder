class MailRemindersController < ApplicationController
  before_filter :find_project
  before_filter :authorize, only: :index

  def index
    needs_refresh = false
    @reminders = MailReminder.where(project_id: @project)
    @reminders.each do |reminder|
      if reminder.query.nil?
        reminder.destroy
        needs_refresh = true
      end
    end
    @reminders = MailReminder.where(project_id: @project) if needs_refresh
    @reminder = MailReminder.new
  end

  def create
    reminder = MailReminder.new(reminder_params)
    reminder.interval_value = params[:interval_value].to_i

    if reminder.save
      Role.find_all_givable.each do |role|
        if params[role.name.downcase]
          rr = ReminderRole.new
          rr.mail_reminder = reminder
          rr.role = role
          rr.save
        end
      end

      flash[:notice] = t(:reminder_created)
    else
      flash[:error] = t(:reminder_not_created)
    end

    render partial: 'reload'
  end

  def update
    reminder = MailReminder.find(params[:id])

    if request.put? && reminder.update_attributes(reminder_params)
      reminder.interval_value = params[:interval_value]
      Role.find_all_givable.each do |role|
        if reminder.roles.include?(role) && params[role.name.downcase].nil?
          reminder.reminder_roles.find_by_role_id(role.id).destroy
        elsif params[role.name.downcase] && !reminder.roles.include?(role)
          rr = ReminderRole.new
          rr.mail_reminder = reminder
          rr.role = role
          rr.save
        end
      end

      reminder.save
    end

    render partial: 'reload'
  end

  def destroy
    reminder = MailReminder.find(params[:id])
    reminder.destroy if reminder

    render partial: 'reload'
  end

  def update_interval_values
    vals = MailReminder.interval_values_for(params[:interval])

    begin
      reminder = MailReminder.find(params[:mail_reminder_id])
    rescue ActiveRecord::RecordNotFound
      reminder = MailReminder.new
    end

    render partial: 'reload'
  end

  private

  def find_project
    if params[:project_id].present?
      @project = Project.find(params[:project_id])
    end
  end

  def authorize
    User.current.admin? && @project.nil? or super
  end

  def reminder_params
    params.require(:reminder).permit(:project_id, :query_id, :interval)
  end
end
