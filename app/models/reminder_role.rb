class ReminderRole < ActiveRecord::Base
  belongs_to :mail_reminder
  belongs_to :role
end
