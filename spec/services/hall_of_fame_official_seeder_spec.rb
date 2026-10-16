# frozen_string_literal: true

require "rails_helper"

RSpec.describe HallOfFame::OfficialSeeder do
  let(:config) do
    {
      "congress"  => [ { "slug" => "pelosi", "last" => "Pelosi", "first" => "Nancy", "district" => "CA11" } ],
      "executive" => [ { "slug" => "vance", "last" => "Vance", "first" => "JD", "title" => "副總統" } ]
    }
  end

  it "creates officials with category, source and display_name" do
    described_class.new(config: config).call

    pelosi = HallOfFame::Official.find_by!(slug: "pelosi")
    expect(pelosi).to have_attributes(category: "congress", source: "house",
                                      display_name: "Nancy Pelosi", district: "CA11", active: true)
    vance = HallOfFame::Official.find_by!(slug: "vance")
    expect(vance).to have_attributes(category: "executive", source: "oge", title: "副總統")
  end

  it "is idempotent" do
    2.times { described_class.new(config: config).call }
    expect(HallOfFame::Official.count).to eq(2)
  end

  it "updates an existing official in place" do
    described_class.new(config: config).call
    changed = config.merge("congress" => [ config["congress"].first.merge("district" => "CA12") ])
    described_class.new(config: changed).call

    expect(HallOfFame::Official.find_by!(slug: "pelosi").district).to eq("CA12")
    expect(HallOfFame::Official.count).to eq(2)
  end

  it "raises on an entry missing required keys and writes nothing" do
    bad = config.merge("executive" => [ { "slug" => "trump", "last" => "Trump" } ])
    expect { described_class.new(config: bad).call }
      .to raise_error(described_class::InvalidConfig, /first/)
    expect(HallOfFame::Official.count).to eq(0)
  end

  it "raises on an unknown category" do
    expect { described_class.new(config: { "senate" => [] }).call }
      .to raise_error(described_class::InvalidConfig, /senate/)
  end

  it "loads the real config with 11 officials" do
    expect(described_class.new.call.size).to eq(11)
  end
end
