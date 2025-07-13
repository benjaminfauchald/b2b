# Phantom Buster Import Enhancement Plan

## Feature Overview
Import people data from Phantom Buster CSV files with automatic field mapping and format detection.

## Analysis Results

### Existing Fields (Already Mapped)
- `profileUrl` → `profile_url`
- `fullName` → `name`
- `companyName` → `company_name`
- `title` → `title`
- `companyId` → `company_id` (as reference)
- `summary` → `bio`
- `location` → `location`
- `connectionDegree` → `connection_degree`
- `profileImageUrl` → `profile_picture_url`
- `name` → `name`
- `linkedInProfileUrl` → `profile_url`

### New Fields to Add
1. **first_name** (string) - Extract from fullName
2. **last_name** (string) - Extract from fullName
3. **company_url** (string) - LinkedIn company URL
4. **regular_company_url** (string) - Regular company website
5. **title_description** (text) - Detailed role description
6. **industry** (string) - Company industry
7. **company_location** (string) - Company headquarters
8. **duration_in_role** (string) - Time in current position
9. **duration_in_company** (string) - Total time at company
10. **past_experience_company_name** (string) - Previous company
11. **past_experience_company_url** (string) - Previous company URL
12. **past_experience_company_title** (string) - Previous role
13. **past_experience_date** (string) - Previous role dates
14. **past_experience_duration** (string) - Previous role duration
15. **shared_connections_count** (integer) - LinkedIn connections
16. **vmid** (string) - LinkedIn internal ID
17. **is_premium** (boolean) - LinkedIn Premium status
18. **is_open_link** (boolean) - LinkedIn OpenLink status
19. **query** (string) - Search query that found this person
20. **default_profile_url** (string) - Canonical LinkedIn URL
21. **phantom_buster_timestamp** (datetime) - Import timestamp

## Implementation Plan

### 1. Database Migration (45 minutes)
Create migration to add new fields to the `people` table with appropriate types and defaults.

### 2. PhantomBusterImportService (2 hours)
- Automatic CSV format detection based on header columns
- Field mapping configuration
- Data validation and sanitization
- Handle LinkedIn URL variations

### 3. Field Mapping Logic (1.5 hours)
- Map CSV columns to database fields
- Parse first/last names from fullName
- Convert string booleans to proper boolean fields
- Handle missing/null values gracefully

### 4. Async Processing (1 hour)
- Create PersonImportJob for background processing
- Batch processing for large files
- Progress tracking and reporting

### 5. Import UI Component (1.5 hours)
- Upload interface on People index page
- Format detection feedback
- Progress bar during import
- Results summary

### 6. Error Handling (1 hour)
- Validate required fields
- Handle duplicate profiles (by profile_url)
- Log import errors with row numbers
- Provide downloadable error report

### 7. Testing (2 hours)
- Unit tests for import service
- Integration tests for full workflow
- UI tests for upload process
- Performance tests for large files

## Technical Design

### PhantomBusterImportService
```ruby
class PhantomBusterImportService
  PHANTOM_BUSTER_HEADERS = %w[
    profileUrl fullName firstName lastName companyName title 
    companyId companyUrl regularCompanyUrl summary titleDescription
    industry companyLocation location durationInRole durationInCompany
    pastExperienceCompanyName pastExperienceCompanyUrl 
    pastExperienceCompanyTitle pastExperienceDate pastExperienceDuration
    connectionDegree profileImageUrl sharedConnectionsCount name vmid
    linkedInProfileUrl isPremium isOpenLink query timestamp defaultProfileUrl
  ].freeze
  
  def detect_format(headers)
    # Check if headers match Phantom Buster format
  end
  
  def import(file_path)
    # Main import logic with validation
  end
  
  private
  
  def map_row_to_person(row)
    # Field mapping logic
  end
end
```

### Import Flow
1. User uploads CSV file
2. System detects Phantom Buster format
3. Shows preview with field mappings
4. User confirms import
5. Background job processes file
6. Progress updates via Turbo
7. Summary shown on completion

### Duplicate Handling
- Use `profile_url` as unique identifier
- Options: Skip, Update, or Create New
- Log all duplicate decisions

### Performance Considerations
- Process in batches of 100 records
- Use `insert_all` for new records
- Index on `profile_url` for fast lookups
- Monitor memory usage for large files

## Questions to Resolve
1. Should we store all past experience data or just the most recent?
2. How should we handle company linking (companyId)?
3. Should we create a separate table for past experiences?
4. What validation rules for LinkedIn URLs?

## Success Criteria
- Automatically recognizes Phantom Buster CSV format
- Imports 500+ records in under 1 minute
- Handles duplicates gracefully
- Provides clear error reporting
- Maintains data integrity