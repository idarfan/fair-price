# frozen_string_literal: true

namespace :options do
  desc "Delete option_snapshots older than 90 days"
  task cleanup: :environment do
    count = OptionSnapshot.where("snapshot_date < ?", 90.days.ago.to_date).delete_all
    puts "Deleted #{count} old option snapshots"
  end
end
