#!/usr/bin/env python3
"""
Simple Sales Navigator scraper - no complex JavaScript, just extract what we can
"""

import os
import json
import asyncio
import re
from scrapfly import ScrapeConfig, ScrapflyClient

SCRAPFLY = ScrapflyClient(key=os.environ.get("SCRAPFLY_API_KEY"))

async def simple_sales_nav_scrape(url: str):
    """Simple scrape without complex JavaScript - extract from current state"""
    
    cookies = {"li_at": os.environ.get("LINKEDIN_COOKIE_LI_AT", "")}
    
    config = ScrapeConfig(
        url,
        cookies=cookies,
        asp=True,
        country="US",
        render_js=True,  # Basic JS rendering
        proxy_pool="public_residential_pool"
    )
    
    try:
        print(f"🚀 Simple scrape of: {url}")
        
        response = await SCRAPFLY.async_scrape(config)
        
        print(f"📄 Response: {response.status_code}")
        print(f"📊 Size: {len(response.content)} bytes")
        
        # Save full response
        os.makedirs("tmp/debug", exist_ok=True)
        with open("tmp/debug/simple_scrape.html", "w", encoding="utf-8") as f:
            f.write(response.content)
        
        # Extract whatever we can find
        profiles = extract_any_profiles(response.content, response.selector)
        
        # Try to extract from JavaScript variables
        js_profiles = extract_from_javascript(response.content)
        profiles.extend(js_profiles)
        
        # Remove duplicates
        unique_profiles = []
        seen = set()
        for profile in profiles:
            key = profile.get('name', '') + profile.get('email', '') + profile.get('profile_url', '')
            if key and key not in seen:
                seen.add(key)
                unique_profiles.append(profile)
        
        result = {
            "success": len(unique_profiles) > 0,
            "profiles": unique_profiles,
            "total_found": len(unique_profiles),
            "url": url,
            "status_code": response.status_code,
            "extraction_methods": list(set([p.get('source', 'unknown') for p in unique_profiles]))
        }
        
        return result
        
    except Exception as e:
        print(f"❌ Error: {e}")
        return {"success": False, "error": str(e), "url": url}

def extract_any_profiles(html_content: str, selector) -> list:
    """Extract any profile data we can find using multiple methods"""
    profiles = []
    
    print("🔍 Extracting profiles using multiple methods...")
    
    # Method 1: Look for profile URLs and extract context
    profile_links = selector.css('a[href*="/in/"], a[href*="/sales/people/"]')
    print(f"  Found {len(profile_links)} profile links")
    
    for link in profile_links:
        href = link.css('::attr(href)').get() or ""
        text = link.css('::text').get() or ""
        
        if text.strip():
            profiles.append({
                "name": text.strip(),
                "profile_url": href if href.startswith('http') else f"https://www.linkedin.com{href}",
                "source": "profile_link"
            })
    
    # Method 2: Look for email addresses and extract context
    email_pattern = r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b'
    emails = re.findall(email_pattern, html_content)
    print(f"  Found {len(emails)} email addresses")
    
    for email in emails:
        if 'linkedin' not in email.lower():  # Skip LinkedIn's own emails
            profiles.append({
                "email": email,
                "source": "email_extraction"
            })
    
    # Method 3: Look for name patterns
    name_patterns = [
        r'"firstName":\s*"([^"]+)"',
        r'"lastName":\s*"([^"]+)"',
        r'"name":\s*"([^"]+)"',
        r'"publicIdentifier":\s*"([^"]+)"'
    ]
    
    names = {}
    for pattern in name_patterns:
        matches = re.findall(pattern, html_content)
        field = pattern.split('"')[1]
        names[field] = matches
    
    # Combine first and last names
    if 'firstName' in names and 'lastName' in names:
        for first, last in zip(names['firstName'], names['lastName']):
            if first and last:
                profiles.append({
                    "name": f"{first} {last}",
                    "source": "json_name_extraction"
                })
    
    # Single names
    if 'name' in names:
        for name in names['name']:
            if name and len(name.split()) >= 2:  # Likely a full name
                profiles.append({
                    "name": name,
                    "source": "json_name_extraction"
                })
    
    # Method 4: Look for structured data
    json_ld_scripts = selector.css('script[type="application/ld+json"]::text').getall()
    for script in json_ld_scripts:
        try:
            data = json.loads(script)
            if isinstance(data, dict):
                # Look for person data
                persons = extract_persons_from_json(data)
                profiles.extend(persons)
        except:
            continue
    
    print(f"  Extracted {len(profiles)} potential profiles")
    return profiles

def extract_from_javascript(html_content: str) -> list:
    """Extract profile data from JavaScript variables"""
    profiles = []
    
    # Look for common LinkedIn JavaScript patterns
    js_patterns = [
        r'voyager.*?firstName.*?lastName',
        r'search.*?results.*?people',
        r'profile.*?data.*?name'
    ]
    
    # Extract JSON-like structures from JavaScript
    json_pattern = r'\{[^{}]*(?:"firstName"|"name"|"publicIdentifier")[^{}]*\}'
    json_matches = re.findall(json_pattern, html_content)
    
    for match in json_matches:
        try:
            # Try to parse as JSON
            data = json.loads(match)
            person = extract_person_from_data(data)
            if person:
                person['source'] = 'javascript_extraction'
                profiles.append(person)
        except:
            # Try to extract manually
            name_match = re.search(r'"(?:firstName|name)":\s*"([^"]+)"', match)
            if name_match:
                profiles.append({
                    "name": name_match.group(1),
                    "source": "javascript_manual_extraction"
                })
    
    return profiles

def extract_persons_from_json(data) -> list:
    """Extract person data from JSON structure"""
    persons = []
    
    def search_json(obj, persons_list):
        if isinstance(obj, dict):
            # Check if this looks like a person object
            if 'firstName' in obj or 'name' in obj:
                person = extract_person_from_data(obj)
                if person:
                    person['source'] = 'json_ld_extraction'
                    persons_list.append(person)
            
            # Recursively search
            for value in obj.values():
                search_json(value, persons_list)
        elif isinstance(obj, list):
            for item in obj:
                search_json(item, persons_list)
    
    search_json(data, persons)
    return persons

def extract_person_from_data(data: dict) -> dict:
    """Extract person data from a data structure"""
    if not isinstance(data, dict):
        return None
    
    person = {}
    
    # Name handling
    if 'firstName' in data and 'lastName' in data:
        person['name'] = f"{data['firstName']} {data['lastName']}".strip()
    elif 'name' in data:
        person['name'] = data['name']
    
    # Other fields
    if 'headline' in data:
        person['title'] = data['headline']
    if 'publicIdentifier' in data:
        person['linkedin_id'] = data['publicIdentifier']
        person['profile_url'] = f"https://www.linkedin.com/in/{data['publicIdentifier']}"
    if 'location' in data:
        person['location'] = data['location']
    if 'company' in data:
        person['company'] = data['company']
    
    # Only return if we have at least a name
    if person.get('name'):
        return person
    
    return None

async def test_simple_scraper():
    """Test the simple scraper approach"""
    
    if not os.environ.get("SCRAPFLY_API_KEY"):
        print("❌ SCRAPFLY_API_KEY required")
        return
    
    target_url = "https://www.linkedin.com/sales/search/people?query=(filters%3AList((type%3ACURRENT_COMPANY%2Cvalues%3AList((id%3A3341537%2CselectionType%3AINCLUDED)))))&sessionId=cWxbdzEXSJSyuYKPOUjGtw%3D%3D"
    
    print("🎯 Testing Simple Sales Navigator Scraper")
    print("=" * 50)
    
    result = await simple_sales_nav_scrape(target_url)
    
    # Save results
    with open("tmp/simple_scraper_results.json", "w", encoding="utf-8") as f:
        json.dump(result, f, indent=2, ensure_ascii=False)
    
    print(f"\n💾 Results saved to tmp/simple_scraper_results.json")
    
    if result.get("success"):
        print(f"🎉 SUCCESS! Found {result['total_found']} profiles")
        print(f"📊 Extraction methods used: {result['extraction_methods']}")
        
        for i, profile in enumerate(result["profiles"][:10]):
            print(f"  {i+1}. {profile.get('name', profile.get('email', 'Unknown'))}")
            if profile.get('title'):
                print(f"      Title: {profile['title']}")
            if profile.get('company'):
                print(f"      Company: {profile['company']}")
            if profile.get('profile_url'):
                print(f"      URL: {profile['profile_url']}")
            print(f"      Source: {profile.get('source', 'unknown')}")
            print()
    else:
        print(f"❌ FAILED: {result.get('error', 'No profiles found')}")
    
    return result

if __name__ == "__main__":
    asyncio.run(test_simple_scraper())