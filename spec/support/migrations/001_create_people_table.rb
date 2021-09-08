# frozen_string_literal: true

Sequel.migration do
  change do
    create_table(:people) do
      String :name, null: false
      Integer :age, null: false
      TrueClass :is_developer, null: false
    end
  end
end
