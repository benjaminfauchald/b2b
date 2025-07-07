# Test for Lillestrøm - LinkedIn Service Enhancement

## Feature Overview
Enhance the LinkedIn Discovery service interface to allow users to specify postal codes and batch sizes for targeted testing. This will enable testing specific geographical regions (like Lillestrøm with postal code 2000) with customizable batch sizes.

## Current State Analysis

### Existing LinkedIn Discovery Architecture
- **Current Service**: `queue_linkedin_discovery` (bulk processing)
- **Individual Service**: `queue_linkedin_discovery_internal` (single company)
- **Interface**: Company Enhancement Queue Component with batch size of 100
- **SQL Query**: Companies are selected by country, not postal code
- **UI**: Fixed batch size input field in enhancement queue

### Current Limitations
1. No postal code filtering capability
2. Fixed batch size in UI
3. No specific geographical targeting
4. Uses general "needing service" query, not revenue-ordered query

## Proposed Solution

### 1. Enhanced LinkedIn Discovery Interface
Create a new interface that allows:
- **Postal Code Selection**: Input field for postal code (default: 2000)
- **Batch Size Selection**: Configurable batch size (default: 100)
- **Revenue Ordering**: Companies ordered by operating revenue (desc)
- **Clear Filtering**: Show exactly which companies will be processed

### 2. Backend Enhancement
- **New Controller Action**: `queue_linkedin_discovery_by_postal_code`
- **Custom Query**: `companies.where(postal_code: code).where.not(operating_revenue: nil).order(operating_revenue: :desc).limit(batch_size)`
- **Validation**: Ensure postal code exists and has companies
- **Service Integration**: Reuse existing LinkedIn discovery service

### 3. UI Components
- **New Component**: `LinkedinDiscoveryPostalCodeComponent`
- **Form Fields**: Postal code input, batch size selector
- **Preview**: Show companies count for selected postal code
- **Styling**: Follow Flowbite/Tailwind patterns

## Implementation Plan

### Phase 1: Backend Foundation (30 min)
1. **Add Route**: New collection route for postal code based queueing
2. **Controller Method**: `queue_linkedin_discovery_by_postal_code`
3. **Query Logic**: Implement SQL query with postal code filtering
4. **Validation**: Postal code validation and company availability checks

### Phase 2: UI Component (45 min)
1. **Create Component**: `LinkedinDiscoveryPostalCodeComponent`
2. **Form Design**: Postal code input, batch size selector
3. **AJAX Integration**: Real-time company count preview
4. **Styling**: Flowbite button and input styling

### Phase 3: Integration (30 min)
1. **Add to Enhancement Queue**: Integrate new component
2. **Navigation**: Add to existing enhancement interface
3. **Testing**: Manual testing with postal code 2000

### Phase 4: Testing & Validation (45 min)
1. **Unit Tests**: Controller action tests
2. **Component Tests**: UI component tests
3. **Integration Tests**: Full workflow testing
4. **Edge Cases**: Invalid postal codes, no companies

### Phase 5: Documentation (15 min)
1. **Update IDM**: Log implementation progress
2. **Code Comments**: Document new functionality
3. **README**: Usage instructions

## Technical Specifications

### Database Query
```sql
SELECT * FROM companies 
WHERE postal_code = '2000' 
AND operating_revenue IS NOT NULL 
ORDER BY operating_revenue DESC 
LIMIT 100;
```

### New Controller Method
```ruby
def queue_linkedin_discovery_by_postal_code
  postal_code = params[:postal_code] || '2000'
  batch_size = params[:batch_size]&.to_i || 100
  
  # Validation and processing logic
  companies = Company.where(postal_code: postal_code)
                    .where.not(operating_revenue: nil)
                    .order(operating_revenue: :desc)
                    .limit(batch_size)
  
  # Queue processing
end
```

### Component Structure
- **Input Fields**: Postal code, batch size
- **Preview Section**: Company count, revenue range
- **Action Button**: Queue processing
- **Status Display**: Processing status

## Success Criteria
1. ✅ User can specify postal code for LinkedIn discovery
2. ✅ User can set custom batch sizes (1-1000)
3. ✅ Companies are ordered by operating revenue (descending)
4. ✅ Real-time preview of companies to be processed
5. ✅ Integration with existing LinkedIn discovery service
6. ✅ Proper error handling and validation
7. ✅ Comprehensive test coverage
8. ✅ Follows existing UI/UX patterns

## Risk Mitigation
- **Service Reuse**: Leverage existing LinkedIn discovery service
- **UI Consistency**: Follow existing component patterns
- **Error Handling**: Comprehensive validation and error messages
- **Performance**: Limit batch sizes to prevent system overload

## Future Enhancements
- **Multi-Postal Code**: Support for multiple postal codes
- **Date Range Filtering**: Filter companies by registration date
- **Revenue Range**: Filter by revenue ranges
- **Export Functionality**: Export company lists before processing

## Estimated Timeline
- **Total**: 2.5 hours
- **Phase 1**: 30 minutes
- **Phase 2**: 45 minutes  
- **Phase 3**: 30 minutes
- **Phase 4**: 45 minutes
- **Phase 5**: 15 minutes

## Dependencies
- Existing LinkedIn discovery service
- Company model with postal_code and operating_revenue fields
- Current enhancement queue UI structure
- Flowbite CSS framework