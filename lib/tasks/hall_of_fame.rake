# frozen_string_literal: true

namespace :hall_of_fame do
  desc "由 config/hall_of_fame.yml 同步名人堂名單至 hof_officials（冪等）"
  task seed_officials: :environment do
    officials = HallOfFame::OfficialSeeder.new.call
    puts "hall_of_fame:seed_officials 同步 #{officials.size} 位；hof_officials 共 #{HallOfFame::Official.count} 筆"
  end
end
