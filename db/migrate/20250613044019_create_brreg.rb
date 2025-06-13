class CreateBrreg < ActiveRecord::Migration[7.1]
  def change
    create_table :brreg do |t|
      t.string :organisasjonsnummer, null: false
      t.text :navn, null: false
      t.text :organisasjonsform_kode
      t.text :organisasjonsform_beskrivelse
      t.text :naeringskode1_kode
      t.text :naeringskode1_beskrivelse
      t.text :naeringskode2_kode
      t.text :naeringskode2_beskrivelse
      t.text :naeringskode3_kode
      t.text :naeringskode3_beskrivelse
      t.text :aktivitet
      t.integer :antallansatte
      t.text :hjemmeside
      t.text :epost
      t.text :telefon
      t.text :mobiltelefon
      t.text :forretningsadresse
      t.text :forretningsadresse_poststed
      t.text :forretningsadresse_postnummer
      t.text :forretningsadresse_kommune
      t.text :forretningsadresse_land
      t.bigint :driftsinntekter
      t.bigint :driftskostnad
      t.bigint :ordinaertResultat
      t.bigint :aarsresultat
      t.boolean :mvaregistrert
      t.date :mvaregistrertdato
      t.boolean :frivilligmvaregistrert
      t.date :frivilligmvaregistrertdato
      t.date :stiftelsesdato
      t.boolean :konkurs
      t.date :konkursdato
      t.boolean :underavvikling
      t.date :avviklingsdato
      t.text :linked_in
      t.text :linked_in_ai
      t.jsonb :linked_in_alternatives
      t.boolean :linked_in_processed, default: false
      t.datetime :linked_in_last_processed_at
      t.integer :http_error
      t.text :http_error_message
      t.jsonb :brreg_result_raw
      t.text :description
      t.timestamps
    end

    add_index :brreg, :organisasjonsnummer, unique: true
    add_index :brreg, :driftsinntekter
    add_index :brreg, :linked_in_ai
    add_index :brreg, :organisasjonsform_beskrivelse
  end
end
