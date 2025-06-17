#!/bin/bash

# Companies Migration Script from b2b.connectica.no to app.connectica.no
# This script directly migrates company data using PostgreSQL

echo "Starting companies migration from remote to local database..."
echo "============================================================"

# Database connection parameters
REMOTE_HOST="b2b.connectica.no"
REMOTE_DB="b2b_development"
REMOTE_USER="postgres"
REMOTE_PASS="Charcoal2020!"

LOCAL_HOST="app.connectica.no"
LOCAL_DB="b2b_production"
LOCAL_USER="benjamin"
LOCAL_PASS="Charcoal2020!"

# Export PGPASSWORD to avoid password prompts
export PGPASSWORD="$REMOTE_PASS"

# Get total count from remote database
echo "Getting record count from remote database..."
TOTAL_REMOTE=$(psql -h "$REMOTE_HOST" -U "$REMOTE_USER" -d "$REMOTE_DB" -t -c "SELECT COUNT(*) FROM companies;" | xargs)
echo "Total remote records: $TOTAL_REMOTE"

# Export local password
export PGPASSWORD="$LOCAL_PASS"

# Get current local count
LOCAL_BEFORE=$(psql -h "$LOCAL_HOST" -U "$LOCAL_USER" -d "$LOCAL_DB" -t -c "SELECT COUNT(*) FROM companies;" | xargs)
echo "Local records before migration: $LOCAL_BEFORE"

# Create temp file for data
TEMP_FILE="/tmp/companies_migration_$(date +%s).sql"

echo "Exporting data from remote database (this may take several minutes)..."
export PGPASSWORD="$REMOTE_PASS"

# Export companies data to CSV file, excluding ID to avoid conflicts
psql -h "$REMOTE_HOST" -U "$REMOTE_USER" -d "$REMOTE_DB" -c "
COPY (
  SELECT 
    source_country,
    source_registry,
    source_id,
    registration_number,
    company_name,
    organization_form_code,
    organization_form_description,
    registration_date,
    deregistration_date,
    deregistration_reason,
    registration_country,
    primary_industry_code,
    primary_industry_description,
    secondary_industry_code,
    secondary_industry_description,
    tertiary_industry_code,
    tertiary_industry_description,
    business_description,
    segment,
    industry,
    has_registered_employees,
    employee_count,
    employee_registration_date_registry,
    employee_registration_date_nav,
    linkedin_employee_count,
    website,
    email,
    phone,
    mobile,
    postal_address,
    postal_city,
    postal_code,
    postal_municipality,
    postal_municipality_code,
    postal_country,
    postal_country_code,
    business_address,
    business_city,
    business_postal_code,
    business_municipality,
    business_municipality_code,
    business_country,
    business_country_code,
    last_submitted_annual_report,
    ordinary_result,
    annual_result,
    operating_revenue,
    operating_costs,
    linkedin_url,
    linkedin_ai_url,
    linkedin_alt_url,
    linkedin_alternatives,
    linkedin_processed,
    linkedin_last_processed_at,
    linkedin_ai_confidence,
    sps_match,
    sps_match_percentage,
    http_error,
    http_error_message,
    source_raw_data,
    brreg_id,
    country,
    description,
    created_at,
    updated_at,
    vat_registered,
    vat_registration_date,
    voluntary_vat_registered,
    voluntary_vat_registration_date,
    bankruptcy,
    bankruptcy_date,
    under_liquidation,
    liquidation_date,
    revenue,
    profit,
    equity,
    total_assets,
    current_assets,
    fixed_assets,
    current_liabilities,
    long_term_liabilities,
    year,
    financial_data
  FROM companies 
  ORDER BY id
) TO STDOUT WITH CSV HEADER;
" > "${TEMP_FILE}.csv"

echo "Creating SQL insert statements..."
cat > "$TEMP_FILE" << 'EOF'
-- Companies migration SQL
BEGIN;

-- Create temporary table for staging
CREATE TEMP TABLE temp_companies (
  source_country VARCHAR(2),
  source_registry VARCHAR(20),
  source_id TEXT,
  registration_number TEXT,
  company_name TEXT,
  organization_form_code TEXT,
  organization_form_description TEXT,
  registration_date DATE,
  deregistration_date DATE,
  deregistration_reason TEXT,
  registration_country TEXT,
  primary_industry_code TEXT,
  primary_industry_description TEXT,
  secondary_industry_code TEXT,
  secondary_industry_description TEXT,
  tertiary_industry_code TEXT,
  tertiary_industry_description TEXT,
  business_description TEXT,
  segment TEXT,
  industry TEXT,
  has_registered_employees BOOLEAN,
  employee_count INTEGER,
  employee_registration_date_registry DATE,
  employee_registration_date_nav DATE,
  linkedin_employee_count INTEGER,
  website TEXT,
  email TEXT,
  phone TEXT,
  mobile TEXT,
  postal_address TEXT,
  postal_city TEXT,
  postal_code TEXT,
  postal_municipality TEXT,
  postal_municipality_code TEXT,
  postal_country TEXT,
  postal_country_code TEXT,
  business_address TEXT,
  business_city TEXT,
  business_postal_code TEXT,
  business_municipality TEXT,
  business_municipality_code TEXT,
  business_country TEXT,
  business_country_code TEXT,
  last_submitted_annual_report INTEGER,
  ordinary_result BIGINT,
  annual_result BIGINT,
  operating_revenue BIGINT,
  operating_costs BIGINT,
  linkedin_url TEXT,
  linkedin_ai_url TEXT,
  linkedin_alt_url TEXT,
  linkedin_alternatives JSONB,
  linkedin_processed BOOLEAN,
  linkedin_last_processed_at TIMESTAMP,
  linkedin_ai_confidence INTEGER,
  sps_match TEXT,
  sps_match_percentage TEXT,
  http_error INTEGER,
  http_error_message TEXT,
  source_raw_data JSONB,
  brreg_id INTEGER,
  country VARCHAR(2),
  description TEXT,
  created_at TIMESTAMP,
  updated_at TIMESTAMP,
  vat_registered BOOLEAN,
  vat_registration_date DATE,
  voluntary_vat_registered BOOLEAN,
  voluntary_vat_registration_date DATE,
  bankruptcy BOOLEAN,
  bankruptcy_date DATE,
  under_liquidation BOOLEAN,
  liquidation_date DATE,
  revenue NUMERIC,
  profit NUMERIC,
  equity NUMERIC,
  total_assets NUMERIC,
  current_assets NUMERIC,
  fixed_assets NUMERIC,
  current_liabilities NUMERIC,
  long_term_liabilities NUMERIC,
  year INTEGER,
  financial_data TEXT
);

EOF

# Add the CSV import command
echo "\\copy temp_companies FROM '${TEMP_FILE}.csv' WITH CSV HEADER;" >> "$TEMP_FILE"

# Add the merge logic
cat >> "$TEMP_FILE" << 'EOF'

-- Insert new companies and update existing ones with ON CONFLICT
INSERT INTO companies (
  source_country, source_registry, source_id, registration_number, company_name,
  organization_form_code, organization_form_description, registration_date, deregistration_date,
  deregistration_reason, registration_country, primary_industry_code, primary_industry_description,
  secondary_industry_code, secondary_industry_description, tertiary_industry_code, tertiary_industry_description,
  business_description, segment, industry, has_registered_employees, employee_count,
  employee_registration_date_registry, employee_registration_date_nav, linkedin_employee_count,
  website, email, phone, mobile, postal_address, postal_city, postal_code,
  postal_municipality, postal_municipality_code, postal_country, postal_country_code,
  business_address, business_city, business_postal_code, business_municipality,
  business_municipality_code, business_country, business_country_code, last_submitted_annual_report,
  ordinary_result, annual_result, operating_revenue, operating_costs, linkedin_url,
  linkedin_ai_url, linkedin_alt_url, linkedin_alternatives, linkedin_processed,
  linkedin_last_processed_at, linkedin_ai_confidence, sps_match, sps_match_percentage,
  http_error, http_error_message, source_raw_data, brreg_id, country, description,
  created_at, updated_at, vat_registered, vat_registration_date, voluntary_vat_registered,
  voluntary_vat_registration_date, bankruptcy, bankruptcy_date, under_liquidation,
  liquidation_date, revenue, profit, equity, total_assets, current_assets,
  fixed_assets, current_liabilities, long_term_liabilities, year, financial_data
)
SELECT 
  t.source_country, t.source_registry, t.source_id, t.registration_number, t.company_name,
  t.organization_form_code, t.organization_form_description, t.registration_date, t.deregistration_date,
  t.deregistration_reason, t.registration_country, t.primary_industry_code, t.primary_industry_description,
  t.secondary_industry_code, t.secondary_industry_description, t.tertiary_industry_code, t.tertiary_industry_description,
  t.business_description, t.segment, t.industry, t.has_registered_employees, t.employee_count,
  t.employee_registration_date_registry, t.employee_registration_date_nav, t.linkedin_employee_count,
  t.website, t.email, t.phone, t.mobile, t.postal_address, t.postal_city, t.postal_code,
  t.postal_municipality, t.postal_municipality_code, t.postal_country, t.postal_country_code,
  t.business_address, t.business_city, t.business_postal_code, t.business_municipality,
  t.business_municipality_code, t.business_country, t.business_country_code, t.last_submitted_annual_report,
  t.ordinary_result, t.annual_result, t.operating_revenue, t.operating_costs, t.linkedin_url,
  t.linkedin_ai_url, t.linkedin_alt_url, t.linkedin_alternatives, t.linkedin_processed,
  t.linkedin_last_processed_at, t.linkedin_ai_confidence, t.sps_match, t.sps_match_percentage,
  t.http_error, t.http_error_message, t.source_raw_data, t.brreg_id, t.country, t.description,
  t.created_at, t.updated_at, t.vat_registered, t.vat_registration_date, t.voluntary_vat_registered,
  t.voluntary_vat_registration_date, t.bankruptcy, t.bankruptcy_date, t.under_liquidation,
  t.liquidation_date, t.revenue, t.profit, t.equity, t.total_assets, t.current_assets,
  t.fixed_assets, t.current_liabilities, t.long_term_liabilities, t.year, t.financial_data
FROM temp_companies t
ON CONFLICT (registration_number) DO NOTHING;

-- Count new records inserted
SELECT 'Migration completed. New records inserted: ' || 
  (SELECT COUNT(*) FROM companies) - 
  (SELECT COUNT(*) FROM temp_companies t JOIN companies c ON c.registration_number = t.registration_number)
  as result;

COMMIT;
EOF

echo "Importing data to local database (this may take several minutes)..."
export PGPASSWORD="$LOCAL_PASS"

# Execute the migration
psql -h "$LOCAL_HOST" -U "$LOCAL_USER" -d "$LOCAL_DB" -f "$TEMP_FILE"

# Get final counts
LOCAL_AFTER=$(psql -h "$LOCAL_HOST" -U "$LOCAL_USER" -d "$LOCAL_DB" -t -c "SELECT COUNT(*) FROM companies;" | xargs)
NET_INCREASE=$((LOCAL_AFTER - LOCAL_BEFORE))

echo ""
echo "============================================================"
echo "Migration completed!"
echo "Remote records: $TOTAL_REMOTE"
echo "Local before: $LOCAL_BEFORE"
echo "Local after: $LOCAL_AFTER"
echo "Net increase: $NET_INCREASE"
echo "============================================================"

# Cleanup
rm -f "$TEMP_FILE" "${TEMP_FILE}.csv"
echo "Temporary files cleaned up."