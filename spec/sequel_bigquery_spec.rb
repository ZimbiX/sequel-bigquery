# frozen-string-literal: true

require 'spec_helper'

RSpec.describe Sequel::Bigquery do
  let(:db) do
    Sequel.connect(
      adapter: :bigquery,
      project: 'greensync-dex-dev',
      database: 'sequel_bigquery_gem',
      logger: Logger.new(STDOUT),
    )
  end

  it 'can connect' do
    expect(db).to be_a(Sequel::Bigquery::Database)
  end
end
