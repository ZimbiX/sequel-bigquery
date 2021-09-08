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
      %w[schema_info people].each do |table_name|
        table(table_name)&.delete
      end
    end

    def table(name)
      dataset.table(name)
    end

    let(:bigquery) { Google::Cloud::Bigquery.new(project: project_name) }
    let(:dataset) { bigquery.dataset(dataset_name) }

    let(:migrations_dir) { 'spec/support/migrations' }

    it 'can migrate' do
      expect(table('schema_info')).to be_nil
      expect(table('people')).to be_nil
      Sequel::Migrator.run(db, migrations_dir)
      expect(table('schema_info')).not_to be_nil
      expect(table('people')).not_to be_nil
    end
  end

  context 'reading/writing rows' do
    let(:person) do
      {
        name: 'Reginald',
        age: 27,
        is_developer: true,
        last_skied_at: last_skied_at,
      }
    end
    let(:last_skied_at) { Time.new(2016, 8, 21, 16, 0, 0, '+08:00') }

    it 'can read back an inserted row' do
      db[:people].truncate
      db[:people].insert(person)
      result = db[:people].where(name: 'Reginald').all
      expect(result).to eq([
        person.merge(last_skied_at: last_skied_at.getlocal)
      ])
    end
  end
end
