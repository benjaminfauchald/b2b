#!/usr/bin/env python3
"""
LinkedIn API Search Script
Uses linkedin-api library to search for profiles and companies
"""

import sys
import json
import logging
from typing import Dict, List, Any, Optional

try:
    from linkedin_api import Linkedin
except ImportError:
    print(json.dumps({
        "success": False,
        "error": "linkedin-api library not installed. Run: pip install linkedin-api"
    }))
    sys.exit(1)

# Set up logging to help with debugging - send to stderr to avoid JSON parsing issues
logging.basicConfig(level=logging.INFO, stream=sys.stderr)
logger = logging.getLogger(__name__)


def authenticate_linkedin(email: str, password: str) -> Optional[Linkedin]:
    """Authenticate with LinkedIn using credentials"""
    try:
        logger.info(f"Authenticating with LinkedIn using email: {email[:4]}***")
        api = Linkedin(email, password)
        logger.info("Successfully authenticated with LinkedIn")
        return api
    except Exception as e:
        logger.error(f"LinkedIn authentication failed: {str(e)}")
        return None


def search_people(api: Linkedin, search_params: Dict[str, Any]) -> List[Dict[str, Any]]:
    """Search for people using linkedin-api"""
    try:
        # Extract search parameters
        keywords = search_params.get('keywords', '')
        company = search_params.get('company', '')
        location = search_params.get('location', '')
        limit = search_params.get('limit', 25)
        
        logger.info(f"Searching people with keywords='{keywords}', company='{company}', location='{location}'")
        
        # Use linkedin-api search_people method
        # Note: linkedin-api uses different parameter names than Sales Navigator
        search_kwargs = {}
        
        if keywords:
            search_kwargs['keywords'] = keywords
        if company:
            search_kwargs['current_company'] = [company]
        if location:
            search_kwargs['regions'] = [location]
        
        # Perform the search
        results = api.search_people(limit=limit, **search_kwargs)
        
        # Transform results to our expected format
        profiles = []
        for person in results:
            profile = {
                'name': person.get('firstName', '') + ' ' + person.get('lastName', ''),
                'headline': person.get('headline', ''),
                'location': person.get('locationName', ''),
                'public_id': person.get('publicIdentifier', ''),
                'profile_url': f"https://www.linkedin.com/in/{person.get('publicIdentifier', '')}/",
                'industry': person.get('industry', ''),
                'summary': person.get('summary', ''),
                'current_company': '',
                'current_position': '',
                'connection_degree': person.get('distance', ''),
                'scraped_at': None  # We'll set this in Ruby
            }
            
            # Extract current company and position from experience
            if 'experience' in person and person['experience']:
                current_exp = person['experience'][0]  # Most recent experience
                profile['current_company'] = current_exp.get('companyName', '')
                profile['current_position'] = current_exp.get('title', '')
            
            profiles.append(profile)
        
        logger.info(f"Successfully found {len(profiles)} profiles")
        return profiles
        
    except Exception as e:
        logger.error(f"People search failed: {str(e)}")
        raise


def get_profile_details(api: Linkedin, public_id: str) -> Dict[str, Any]:
    """Get detailed profile information"""
    try:
        logger.info(f"Getting profile details for: {public_id}")
        
        profile_data = api.get_profile(public_id)
        
        # Transform to our expected format
        profile = {
            'name': profile_data.get('firstName', '') + ' ' + profile_data.get('lastName', ''),
            'headline': profile_data.get('headline', ''),
            'location': profile_data.get('locationName', ''),
            'public_id': public_id,
            'profile_url': f"https://www.linkedin.com/in/{public_id}/",
            'industry': profile_data.get('industryName', ''),
            'summary': profile_data.get('summary', ''),
            'current_company': '',
            'current_position': '',
            'experience': profile_data.get('experience', []),
            'education': profile_data.get('education', []),
            'skills': profile_data.get('skills', []),
            'scraped_at': None  # We'll set this in Ruby
        }
        
        # Extract current company and position
        if profile_data.get('experience'):
            current_exp = profile_data['experience'][0]
            profile['current_company'] = current_exp.get('companyName', '')
            profile['current_position'] = current_exp.get('title', '')
        
        logger.info(f"Successfully retrieved profile for {public_id}")
        return profile
        
    except Exception as e:
        logger.error(f"Profile lookup failed for {public_id}: {str(e)}")
        raise


def main():
    """Main function to handle command line arguments"""
    if len(sys.argv) < 4:
        print(json.dumps({
            "success": False,
            "error": "Usage: python linkedin_search.py <command> <email> <password> [params]"
        }))
        sys.exit(1)
    
    command = sys.argv[1]
    email = sys.argv[2]
    password = sys.argv[3]
    
    # Authenticate with LinkedIn
    api = authenticate_linkedin(email, password)
    if not api:
        print(json.dumps({
            "success": False,
            "error": "Failed to authenticate with LinkedIn"
        }))
        sys.exit(1)
    
    try:
        if command == 'search':
            if len(sys.argv) < 5:
                print(json.dumps({
                    "success": False,
                    "error": "Search command requires search parameters as JSON"
                }))
                sys.exit(1)
            
            search_params = json.loads(sys.argv[4])
            profiles = search_people(api, search_params)
            
            print(json.dumps({
                "success": True,
                "profiles": profiles
            }))
            
        elif command == 'profile':
            if len(sys.argv) < 5:
                print(json.dumps({
                    "success": False,
                    "error": "Profile command requires public_id parameter"
                }))
                sys.exit(1)
            
            public_id = sys.argv[4]
            profile = get_profile_details(api, public_id)
            
            print(json.dumps({
                "success": True,
                "profile": profile
            }))
            
        else:
            print(json.dumps({
                "success": False,
                "error": f"Unknown command: {command}"
            }))
            sys.exit(1)
            
    except Exception as e:
        print(json.dumps({
            "success": False,
            "error": str(e)
        }))
        sys.exit(1)


if __name__ == "__main__":
    main()
