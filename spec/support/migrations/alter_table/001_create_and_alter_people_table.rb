# frozen_string_literal: true

Sequel.migration do
  change do
    create_table(:alter_people) do
      String :a
    end

    alter_table(:alter_people) do
      add_column :col1, String
      add_column :col2, String
      add_column :col3, String
      add_column :col4, String
      add_column :col5, String
      add_column :col6, String
      add_column :col7, String
      add_column :col8, String
      add_column :col9, String
      add_column :col10, String
      add_column :col11, String
      add_column :col12, String
    end
  end
end
