# frozen-string-literal: true

require 'spec_helper'

Sequel.extension :migration

RSpec.describe Sequel::Bigquery do # rubocop:disable RSpec/FilePath
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
  let(:bigquery) { Google::Cloud::Bigquery.new(project: project_name) }
  let(:dataset) { bigquery.dataset(dataset_name) }
  let(:migrations_dir) { 'spec/support/migrations/general' }

  def recreate_dataset(name = dataset_name)
    delete_dataset(name)
    create_dataset(name)
  end

  def delete_dataset(name = dataset_name)
    dataset_to_drop = bigquery.dataset(name)
    return unless dataset_to_drop

    dataset_to_drop.tables.each(&:delete)
    dataset_to_drop.delete
  end

  def create_dataset(name = dataset_name)
    bigquery.create_dataset(name)
  rescue Google::Cloud::AlreadyExistsError
    # cool
  end

  def table(name)
    dataset.table(name)
  end

  it 'can connect' do
    expect(db).to be_a(Sequel::Bigquery::Database)
  end

  describe 'migrating' do
    before do
      recreate_dataset
    end

    it 'can migrate' do
      expect(table('schema_info')).to be_nil
      expect(table('people')).to be_nil
      Sequel::Migrator.run(db, migrations_dir)
      expect(table('schema_info')).not_to be_nil
      expect(table('people')).not_to be_nil
    end
  end

  describe 'reading/writing rows' do
    before do
      delete_dataset
      Sequel::Migrator.run(db, migrations_dir)
    end

    let(:person) do
      {
        name: 'Reginald',
        age: 27,
        is_developer: true,
        last_skied_at: last_skied_at,
        date_of_birth: Date.new(1994, 1, 31),
        height_m: 1.870672173,
        distance_from_sun_million_km: 149.22,
      }
    end
    let(:last_skied_at) { Time.new(2016, 8, 21, 16, 0, 0, '+08:00') }

    it 'can read back an inserted row' do # rubocop:disable RSpec/ExampleLength
      db[:people].truncate
      db[:people].insert(person)
      result = db[:people].where(name: 'Reginald').all
      expect(result).to eq([
        person.merge(last_skied_at: last_skied_at.getlocal),
      ])
    end
  end

  describe 'dropping datasets' do
    let(:second_dataset_name) { 'another_test_dataset' }

    before do
      delete_dataset
      Sequel::Migrator.run(db, migrations_dir)
      recreate_dataset(second_dataset_name)
    end

    it 'can drop a dataset' do
      db.drop_dataset(dataset_name)

      expect(bigquery.datasets).not_to include(dataset_name)
    end

    it 'can drop multiple dataset' do
      db.drop_datasets(dataset_name, second_dataset_name)

      expect(bigquery.datasets).not_to include(dataset_name, second_dataset_name)
    end
  end

  describe 'paritioning tables' do
    let(:migrations_dir) { 'spec/support/migrations/partitioning' }
    let(:expected_sql) { 'CREATE TABLE `partitioned_people` (`name` string, `date_of_birth` date) PARTITION BY (`date_of_birth`)' }

    before do
      recreate_dataset

      allow(Google::Cloud::Bigquery).to receive(:new).and_return(bigquery)
      allow(bigquery).to receive(:dataset).and_return(dataset)
      allow(dataset).to receive(:query).and_call_original

      Sequel::Migrator.run(db, migrations_dir)
    end

    it 'supports partitioning arguments' do
      expect(dataset).to have_received(:query).with(expected_sql)
    end
  end
end
