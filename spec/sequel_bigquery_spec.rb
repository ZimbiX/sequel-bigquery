# frozen-string-literal: true

require 'spec_helper'

Sequel.extension :migration

RSpec.describe Sequel::Bigquery do
  let(:db) do
    Sequel.connect(
      adapter: :bigquery,
      project: project_name,
      database: dataset_name,
      logger: Logger.new(STDOUT),
    )
  end
  let(:project_name) { 'greensync-dex-dev' }
  let(:dataset_name) { 'sequel_bigquery_gem' }

  it 'can connect' do
    expect(db).to be_a(Sequel::Bigquery::Database)
  end

  context 'migrating' do
    before { delete_schema_info_table }

    def delete_schema_info_table
      schema_info_table&.delete
    end

    def schema_info_table
      dataset.table('schema_info')
    end

    let(:bigquery) { Google::Cloud::Bigquery.new(project: project_name) }
    let(:dataset) { bigquery.dataset(dataset_name) }

    let(:migrations_dir) { 'spec/support/migrations' }

    it 'can migrate' do
      expect(schema_info_table).to be_nil
      Sequel::Migrator.run(db, migrations_dir)
      expect(schema_info_table).not_to be_nil
    end
  end
end
