# ZeroBounce Email Verification Documentation

## Overview

ZeroBounce is a comprehensive email verification service that provides detailed analysis of email addresses including deliverability status, domain information, and additional data points for enhanced email marketing and data quality.

## CSV Fields Reference

### Core Verification Fields

| Field Name | Description | Type | Example Values |
|------------|-------------|------|----------------|
| **ZB Status** | Primary verification status | String | `valid`, `invalid`, `catch-all`, `unknown`, `spamtrap`, `abuse`, `do_not_mail` |
| **ZB Sub status** | Detailed sub-status information | String | `mailbox_not_found`, `no_dns_entries`, `failed_smtp_connection`, `mailbox_quota_exceeded`, `exception_occurred`, `possible_trap`, `role_based`, `global_suppression`, `timeout_exceeded`, `mail_server_temporary_error`, `mail_server_did_not_respond`, `greylisted`, `antispam_system`, `does_not_accept_mail`, `alias_address` |

### Domain & Technical Analysis

| Field Name | Description | Type | Example Values |
|------------|-------------|------|----------------|
| **ZB Account** | Account/mailbox information | String | Account details or empty |
| **ZB Domain** | Domain analysis and information | String | Domain status or empty |
| **ZB MX Found** | MX record existence check | Boolean | `true`, `false` |
| **ZB MX Record** | MX record details | String | MX server information |
| **ZB SMTP Provider** | SMTP provider identification | String | `gmail`, `outlook`, `yahoo`, etc. |

### Personal Information Extraction

| Field Name | Description | Type | Example Values |
|------------|-------------|------|----------------|
| **ZB First Name** | Extracted first name | String | First name or empty |
| **ZB Last Name** | Extracted last name | String | Last name or empty |
| **ZB Gender** | Gender inference | String | `male`, `female`, `unknown` |

### Email Quality & Suggestions

| Field Name | Description | Type | Example Values |
|------------|-------------|------|----------------|
| **ZB Free Email** | Free email provider detection | Boolean | `true`, `false` |
| **ZB Did You Mean** | Typo correction suggestion | String | Suggested email or empty |
| **ZeroBounceQualityScore** | Overall quality score | Integer | `0-10` (10 being highest quality) |

### Activity & Engagement Data

| Field Name | Description | Type | Example Values |
|------------|-------------|------|----------------|
| **ZB Last Known Activity** | Last activity timestamp | DateTime | ISO 8601 format or empty |
| **ZB Activity Data Count** | Number of activity data points | Integer | Count or `0` |
| **ZB Activity Data Types** | Types of tracked activity | String | Comma-separated activity types |
| **ZB Activity Data Channels** | Communication channels used | String | Comma-separated channel types |

## Status Codes Reference

### Primary Status Codes

- **`valid`** - Email address exists and is deliverable
- **`invalid`** - Email address does not exist or is not deliverable  
- **`catch-all`** - Domain accepts all emails (cannot determine specific validity)
- **`unknown`** - Status could not be determined due to server limitations
- **`spamtrap`** - Email is a known spam trap
- **`abuse`** - Email is associated with abuse complaints
- **`do_not_mail`** - Email should not be mailed to

### Sub-Status Codes

#### Invalid Email Reasons
- **`mailbox_not_found`** - Mailbox does not exist
- **`no_dns_entries`** - Domain has no DNS entries
- **`failed_smtp_connection`** - Could not connect to mail server
- **`mailbox_quota_exceeded`** - Recipient's mailbox is full
- **`role_based`** - Role-based email (info@, support@, etc.)

#### Technical Issues
- **`timeout_exceeded`** - Server response timeout
- **`mail_server_temporary_error`** - Temporary server error
- **`mail_server_did_not_respond`** - Mail server unresponsive
- **`greylisted`** - Email was greylisted by server
- **`antispam_system`** - Blocked by anti-spam system
- **`does_not_accept_mail`** - Domain does not accept mail

#### Special Cases
- **`exception_occurred`** - Unexpected error during verification
- **`possible_trap`** - Potentially a spam trap
- **`global_suppression`** - Email on global suppression list
- **`alias_address`** - Email is an alias

## Quality Score Interpretation

| Score Range | Quality Level | Recommended Action |
|-------------|---------------|-------------------|
| **9-10** | Excellent | Safe to mail, high deliverability |
| **7-8** | Good | Generally safe to mail |
| **5-6** | Fair | Use with caution, monitor engagement |
| **3-4** | Poor | Consider additional verification |
| **0-2** | Very Poor | Do not mail, likely problematic |

## Best Practices

### Email List Management
- Use `valid` status emails for primary campaigns
- Segment `catch-all` emails for separate testing
- Remove `invalid`, `spamtrap`, and `abuse` emails immediately
- Monitor `unknown` emails and reverify periodically

### Data Integration
- Store original email alongside ZeroBounce results
- Track verification timestamps for data freshness
- Use quality scores for email prioritization
- Leverage activity data for engagement insights

### Performance Optimization
- Batch process emails for better API efficiency
- Cache results to avoid redundant API calls
- Implement retry logic for transient errors
- Monitor API usage and rate limits

## Common Use Cases

### Lead Scoring
Combine ZeroBounce quality scores with other lead qualification metrics:
```
Total Lead Score = Base Score + (ZB Quality Score * Weight)
```

### List Segmentation
- **High Value**: `valid` + Quality Score ≥ 8
- **Medium Value**: `valid` + Quality Score 5-7  
- **Low Value**: `catch-all` or Quality Score < 5
- **Exclude**: `invalid`, `spamtrap`, `abuse`, `do_not_mail`

### Data Enrichment
Use extracted personal information (first name, last name, gender) to:
- Personalize email campaigns
- Improve CRM data quality
- Enhanced lead profiling

## Integration Notes

- ZeroBounce results should be stored alongside original email data
- Consider verification freshness when making mailing decisions
- Free email detection can inform B2B vs B2C targeting strategies
- Activity data provides valuable engagement insights for marketing

## API Rate Limits & Costs

- Check current API documentation for rate limits
- Consider bulk verification for large datasets
- Monitor credit usage and billing
- Implement appropriate error handling and retry logic