class RenamePhantomBusterCompanyIdToLinkedinCompanyIdInPeople < ActiveRecord::Migration[8.0]
  def change
    rename_column :people, :phantom_buster_company_id, :linkedin_company_id
  end
end
