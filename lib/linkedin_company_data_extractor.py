#!/usr/bin/env python3
"""
LinkedIn Company Data Extractor Script
Ruby-callable Python script for extracting LinkedIn company data
"""

import sys
import json
import argparse
import logging
from typing import Dict, Any, Optional

try:
    from linkedin_api import Linkedin
except ImportError:
    print(json.dumps({
        "success": False,
        "error": "linkedin-api library not installed. Run: pip install linkedin-api"
    }))
    sys.exit(1)

# Configure logging
logging.basicConfig(level=logging.WARNING)
logger = logging.getLogger(__name__)


def authenticate_linkedin(email: str = None, password: str = None, 
                         li_at_cookie: str = None, jsessionid_cookie: str = None) -> Optional[Linkedin]:
    """Authenticate with LinkedIn using credentials or cookies"""
    try:
        if li_at_cookie:
            logger.info("Authenticating with cookies")
            cookies = {'li_at': li_at_cookie}
            if jsessionid_cookie:
                cookies['JSESSIONID'] = jsessionid_cookie
            api = Linkedin(email or "", password or "", cookies=cookies)
        else:
            logger.info(f"Authenticating with username/password")
            api = Linkedin(email, password)
        
        return api
    except Exception as e:
        logger.error(f"Authentication failed: {str(e)}")
        return None


def extract_company_id_from_entity_urn(entity_urn: str) -> Optional[str]:
    """Extract company ID from LinkedIn entity URN"""
    if not entity_urn:
        return None
    
    # Format: urn:li:fs_normalized_company:1035
    parts = entity_urn.split(':')
    if len(parts) >= 4:
        return parts[-1]
    return None


def get_company_data(api: Linkedin, company_identifier: str) -> Dict[str, Any]:
    """Get company data from LinkedIn API"""
    try:
        logger.info(f"Fetching company data for: {company_identifier}")
        
        # Use the get_company method from linkedin_api
        company_data = api.get_company(company_identifier)
        
        if not company_data:
            return {
                "success": False,
                "error": f"Company not found: {company_identifier}"
            }
        
        # Extract company ID from entity URN
        entity_urn = company_data.get('entityUrn', '')
        extracted_id = extract_company_id_from_entity_urn(entity_urn)
        
        # Get industry information
        industry = None
        if company_data.get('companyIndustries'):
            industry = company_data['companyIndustries'][0].get('localizedName')
        
        # Build standardized response
        result = {
            "success": True,
            "data": {
                "id": extracted_id,
                "name": company_data.get('name'),
                "universal_name": company_data.get('universalName'),
                "description": company_data.get('description'),
                "website": company_data.get('companyPageUrl'),
                "industry": industry,
                "staff_count": company_data.get('staffCount'),
                "follower_count": company_data.get('staffCount'),  # Using staff count as proxy
                "headquarters": None,
                "founded_year": None,
                "company_type": None,
                "specialties": company_data.get('specialities', []),
                "logo_url": None,
                "entity_urn": entity_urn,
                "raw_data": company_data
            }
        }
        
        # Extract headquarters information
        if company_data.get('headquarter'):
            hq = company_data['headquarter']
            result["data"]["headquarters"] = {
                "city": hq.get('city'),
                "country": hq.get('country'),
                "geographic_area": hq.get('geographicArea'),
                "postal_code": hq.get('postalCode'),
                "line1": hq.get('line1'),
                "line2": hq.get('line2')
            }
        
        # Extract logo URL
        if company_data.get('logo', {}).get('image'):
            artifacts = company_data['logo']['image'].get('com.linkedin.common.VectorImage', {}).get('artifacts', [])
            if artifacts:
                # Get the largest available logo
                largest_logo = max(artifacts, key=lambda x: x.get('width', 0))
                root_url = company_data['logo']['image']['com.linkedin.common.VectorImage'].get('rootUrl', '')
                result["data"]["logo_url"] = root_url + largest_logo.get('fileIdentifyingUrlPathSegment', '')
        
        # Extract company type
        if company_data.get('companyType'):
            result["data"]["company_type"] = company_data['companyType'].get('localizedName')
        
        logger.info(f"Successfully retrieved data for {company_identifier}")
        return result
        
    except Exception as e:
        logger.error(f"Failed to get company data: {str(e)}")
        return {
            "success": False,
            "error": f"Failed to retrieve company data: {str(e)}"
        }


def main():
    """Main function to handle command line arguments"""
    parser = argparse.ArgumentParser(description='LinkedIn Company Data Extractor')
    parser.add_argument('company_identifier', help='LinkedIn company ID or slug')
    parser.add_argument('--email', help='LinkedIn email')
    parser.add_argument('--password', help='LinkedIn password')
    parser.add_argument('--cookie-li-at', help='LinkedIn li_at cookie')
    parser.add_argument('--cookie-jsessionid', help='LinkedIn JSESSIONID cookie')
    
    args = parser.parse_args()
    
    # Authenticate with LinkedIn
    api = authenticate_linkedin(
        email=args.email,
        password=args.password,
        li_at_cookie=args.cookie_li_at,
        jsessionid_cookie=args.cookie_jsessionid
    )
    
    if not api:
        print(json.dumps({
            "success": False,
            "error": "Failed to authenticate with LinkedIn"
        }))
        sys.exit(1)
    
    # Get company data
    result = get_company_data(api, args.company_identifier)
    
    # Output JSON result
    print(json.dumps(result))
    
    if not result["success"]:
        sys.exit(1)


if __name__ == "__main__":
    main()
