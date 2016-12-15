namespace :reminder do
  desc "Executes all reminders that fulfill time conditions."
  task :exec, [:test] => :environment do |task, args|
    require 'set'
    require 'colorize'
    mail_data = Hash.new{|h, k| h[k] = Set.new}
    reminders = MailReminder.select do |rem|
      if rem.project
        next(false) until rem.project.enabled_module_names.include?('issue_reminder')
        next(false) until rem.query.present?
        print "Project \"#{ rem.project.name }\" with query \"#{ rem.query.name }\" "
        if args.test == "test"
          puts "\t is forced processing under [test] mode.".yellow
          next(true)
        end
        if rem.execute?
          puts "\t is processing.".light_blue
          next(true)
        else
          puts "\t is ignored. It's executed recently and too early for next execution.".red
          next(false)
        end
      end
    end
    reminders.
      sort{|l,r| l.project_id <=> r.project_id}.
      each do |rem|
        rem.roles.each do |role|
          role.members.
            select {|m| m.project_id == rem.project_id}.
            reject {|m| m.user.nil? || m.user.locked?}.
            each do |member|
              mail_data[member.user] << [rem.project, rem.query]
              rem.executed_at = Time.now if args.test != "test"
              rem.save
            end
        end
      end

      # Fixed: reminder mails are not sent when delivery_method is :async_smtp (#5058).
      MailReminderMailer.with_synched_deliveries do
        mail_data.each do |user, queries_data|
          MailReminderMailer.issues_reminder(user, queries_data).deliver if user.active?
          puts user.mail
        end
      end
  end
end

namespace :redmine_mail_reminder do
  task :send_reminders => :environment do
    Rails.logger = Logger.new(STDOUT)

    reminders = MailReminder.all.to_a

    # reminders.select! do |reminder|
    #   reminder.project.nil? || reminder.project.enabled_module_names.include?('issue_reminder') \
    #   and reminder.execute?
    # end

    byebug

    user_queries = Hash.new { |h, k| h[k] = Set.new }

    reminders.each do |reminder|
      # Find users with given roles
      user_ids = MemberRole.joins(:member)
                   .where(role_id: reminder.role_ids)
      if reminder.project_id
        user_ids = user_ids.where(members: { project_id: reminder.project_id })
      end
      user_ids = user_ids.pluck('DISTINCT user_id')
      users = User.active.where(id: user_ids)

      users.each do |user|
        puts "Query##{reminder.query_id} for User##{user.id}"
        user_queries[user] << reminder.query
      end

      #reminder.executed_at = Time.now
      reminder.save
    end

    MailReminderMailer.with_synched_deliveries do
      user_queries.each do |user, queries|
        next if queries.empty?

        mail = MailReminderMailer.queries_breakdown(user, queries)

        mail.deliver if mail
      end
    end

    byebug
  end
end
