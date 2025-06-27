# Domain CSV Import Implementation Plan

## Overview
Implement robust CSV import functionality for the Domain model using smarter_csv gem, following Rails best practices, and providing an excellent UX with Tailwind/Flowbite components.

## Architecture & Design Decisions

### 1. Service-Oriented Architecture
- **DomainImportService**: Core service handling CSV processing and domain creation
- **DomainImportResultsService**: Service for formatting and presenting import results
- **File validation service**: Validate CSV files before processing

### 2. Error Handling Strategy
- **Row-level validation**: Track success/failure for each CSV row
- **Detailed error messages**: Provide specific feedback for each validation failure
- **Graceful degradation**: Continue processing valid rows even if some fail
- **Transaction safety**: Use database transactions appropriately

### 3. User Experience Design
- **Drag-and-drop upload**: Modern file upload component
- **Progress indicators**: Show upload and processing progress
- **Real-time feedback**: Immediate validation and results display
- **Responsive design**: Works well on all device sizes

### 4. Scalability Considerations
- **Memory efficient**: Stream processing for large files
- **Background job ready**: Architecture supports moving to background processing
- **Rate limiting**: Prevent abuse and system overload

## Technical Implementation

### 1. Dependencies
```ruby
# Gemfile additions
gem 'smarter_csv', '~> 1.8.0'  # Latest stable version for robust CSV parsing
gem 'image_processing', '~> 1.2'  # For file validation if needed
```

### 2. CSV File Format
```csv
domain,dns,www,mx
example.com,true,true,false
test.org,false,false,true
domain.co,,true,
```

**Expected columns:**
- `domain` (required): Domain name
- `dns` (optional): Boolean for DNS status
- `www` (optional): Boolean for WWW status  
- `mx` (optional): Boolean for MX status

### 3. Service Architecture

#### DomainImportService
```ruby
class DomainImportService < ApplicationService
  def initialize(file:, user:)
  def perform
  private
    def process_csv_file
    def create_domain_from_row(row)
    def validate_csv_structure(csv_data)
    def build_import_results
end
```

#### Features:
- **Validation**: File format, size, and content validation
- **Processing**: Row-by-row domain creation with error handling
- **Results**: Detailed success/failure reporting
- **Auditing**: Integration with existing ServiceAuditable system

### 4. UI Components

#### CsvUploadComponent
- **File drag-and-drop zone** using Flowbite styling
- **File validation feedback** (type, size, format)
- **Upload progress indicator**
- **Integration with Rails UJS** for seamless form submission

#### ImportResultsComponent  
- **Success/failure summary** with clear metrics
- **Detailed error list** with row numbers and reasons
- **Actions**: Download error report, view imported domains
- **Responsive table** for mobile-friendly error display

### 5. Controller Structure
```ruby
class DomainsController < ApplicationController
  def import_csv     # GET: Show import form
  def process_import # POST: Handle CSV upload and processing
  def import_results # GET: Display import results
end
```

### 6. Security & Validation

#### File Security
- **MIME type validation**: Only allow CSV/text files
- **File size limits**: Prevent oversized uploads
- **Virus scanning**: Consider integration if needed
- **Temporary file cleanup**: Ensure uploaded files are cleaned up

#### Data Validation
- **Domain format validation**: Use proper regex for domain names
- **Duplicate prevention**: Handle domain uniqueness properly
- **SQL injection prevention**: Use parameterized queries
- **XSS prevention**: Sanitize all user input

### 7. Performance Considerations

#### Memory Management
- **Streaming processing**: Process CSV in chunks to avoid memory issues
- **Batch operations**: Use bulk insert operations where possible
- **Connection pooling**: Manage database connections efficiently

#### User Experience
- **Progressive feedback**: Show progress during long imports
- **Timeout handling**: Gracefully handle long-running operations
- **Error recovery**: Allow users to retry failed imports

## Testing Strategy

### 1. Unit Tests
- **Service tests**: Comprehensive coverage of DomainImportService
- **Model tests**: Domain validation and creation
- **Component tests**: UI component rendering and behavior
- **Helper tests**: Utility methods and formatters

### 2. Integration Tests
- **Controller tests**: End-to-end request/response cycles
- **File upload tests**: Complete file processing workflows
- **Error handling tests**: Various failure scenarios
- **Performance tests**: Large file processing

### 3. Test Data
- **Valid CSV samples**: Different valid formats and data
- **Invalid CSV samples**: Various error conditions
- **Edge cases**: Empty files, malformed data, special characters
- **Performance data**: Large datasets for load testing

### 4. Security Tests
- **File type validation**: Ensure only CSV files are accepted
- **Malicious content**: Test with potentially harmful CSV content
- **Authorization**: Verify proper access controls
- **Input sanitization**: Test XSS and injection prevention

## Implementation Phases

### Phase 1: Core Functionality (MVP)
1. ✅ Add smarter_csv gem
2. ✅ Create DomainImportService with basic CSV processing
3. ✅ Add simple file upload form
4. ✅ Basic success/error reporting
5. ✅ Comprehensive test suite

### Phase 2: Enhanced UX
1. ⏳ Drag-and-drop upload component
2. ⏳ Real-time validation feedback
3. ⏳ Progress indicators
4. ⏳ Responsive design improvements

### Phase 3: Advanced Features
1. 🔮 Background job processing for large files
2. 🔮 Import history and audit trail
3. 🔮 CSV export functionality
4. 🔮 Advanced filtering and sorting

### Phase 4: Production Readiness
1. 🔮 Performance optimization
2. 🔮 Monitoring and alerting
3. 🔮 Documentation and user guides
4. 🔮 Admin dashboard integration

## File Structure
```
app/
├── components/
│   ├── csv_upload_component/
│   │   ├── csv_upload_component.rb
│   │   └── csv_upload_component.html.erb
│   └── import_results_component/
│       ├── import_results_component.rb
│       └── import_results_component.html.erb
├── controllers/
│   └── domains_controller.rb (enhanced)
├── services/
│   ├── domain_import_service.rb
│   └── domain_import_results_service.rb
└── models/
    └── domain.rb (enhanced validations)

spec/
├── components/
├── services/
├── models/
└── requests/

```

## Success Metrics
- **Functionality**: 100% test coverage on import logic
- **Performance**: Handle 10,000+ domain imports under 30 seconds
- **UX**: Zero-click file validation and clear error reporting
- **Security**: Pass security audit with no critical vulnerabilities
- **Maintainability**: Follow Rails conventions and document patterns

This plan ensures a robust, scalable, and user-friendly CSV import feature that follows industry best practices.