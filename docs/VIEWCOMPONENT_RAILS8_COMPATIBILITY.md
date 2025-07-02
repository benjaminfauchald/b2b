# ViewComponent Rails 8 Compatibility Guide

## Overview
This document explains the ViewComponent Rails 8 compatibility issues we've resolved and how to prevent future test crashes. ViewComponent and Rails 8 have specific incompatibilities that require careful handling.

## The Core Problem
Rails 8 freezes `autoload_paths` much earlier in the boot process than previous versions. ViewComponent's engine tries to modify these paths during initialization, causing `FrozenError` in production and CI environments.

## Our Solution Architecture

### 1. Boot-Level Protection (`config/boot.rb`)
```ruby
# Prevents Array#unshift on frozen autoload_paths in CI/test environments
if ENV["CI"] || ENV["RAILS_ENV"] == "test"
  class Array
    alias_method :original_unshift, :unshift
    def unshift(*args)
      if frozen? && caller.any? { |line| line.include?("rails/engine.rb") }
        puts "Rails 8 CI: Prevented unshift to frozen autoload_paths from Rails engine"
        return self
      end
      original_unshift(*args)
    end
  end
end
```

### 2. ViewComponent Engine Patch (`config/initializers/viewcomponent_rails8_compatibility.rb`)
- Overrides ViewComponent::Engine's `set_autoload_paths` method
- Prevents modification of frozen autoload_paths
- Ensures compatibility with Rails 8's stricter initialization

### 3. Manual Autoload Configuration (`config/application.rb`)
- Autoload paths are configured BEFORE Rails freezes them
- ViewComponent paths are added early in the boot process

### 4. Production Template Precompilation
- Templates are precompiled during deployment for Propshaft compatibility
- Rake task: `rake viewcomponent:precompile`

## CI/CD Test Requirements

### Component Instantiation Tests
When testing ViewComponent in CI, ensure all required parameters are provided:

```ruby
# ❌ WRONG - Will fail with "missing keyword: text"
ButtonComponent.new

# ✅ CORRECT - Provides required parameters
ButtonComponent.new(text: 'Test Button')
```

### CI Workflow Checks
The CI workflow includes ViewComponent compatibility tests:
1. Component instantiation verification
2. Template compilation checks
3. Rendering compatibility tests

## Common Issues and Solutions

### Issue 1: FrozenError in Production
**Symptom**: `can't modify frozen Array: [...]` errors in production logs
**Solution**: Ensure all ViewComponent compatibility patches are loaded

### Issue 2: Missing Required Parameters
**Symptom**: `ArgumentError: missing keyword: [parameter_name]`
**Solution**: Check component initializers and provide all required parameters

### Issue 3: Template Compilation Errors
**Symptom**: ViewComponent templates not rendering in production
**Solution**: Run `rake viewcomponent:precompile` during deployment

## Testing Best Practices

1. **Always Test Component Instantiation**
   ```ruby
   # In specs
   it "can be instantiated with required parameters" do
     component = ButtonComponent.new(text: "Click me")
     expect(component).to be_present
   end
   ```

2. **Use Factory Pattern for Complex Components**
   ```ruby
   def create_button_component(text: "Default", **options)
     ButtonComponent.new(text: text, **options)
   end
   ```

3. **CI Environment Variables**
   - Ensure `RAILS_ENV=test` in CI
   - Boot-level patches activate based on these variables

## Monitoring and Debugging

### Check ViewComponent Status
```bash
# Verify ViewComponent is properly loaded
rails runner "puts ViewComponent::VERSION"

# Test component instantiation
rails runner "ButtonComponent.new(text: 'Test')"

# Verify template compilation
rake viewcomponent:verify
```

### Debug Autoload Issues
```bash
# Check if autoload_paths are frozen
rails runner "puts Rails.autoloaders.main.dirs.frozen?"

# List ViewComponent paths
rails runner "puts Rails.autoloaders.main.dirs.grep(/view_component/)"
```

## DO NOT MODIFY These Files
The following files contain critical Rails 8 compatibility fixes:
- `config/boot.rb` - Array monkey patch for CI
- `config/initializers/viewcomponent_rails8_compatibility.rb` - Engine patches
- `config/application.rb` - Manual autoload configuration
- `lib/tasks/viewcomponent_rails8.rake` - Verification tasks

## Future Considerations
- Monitor ViewComponent gem updates for official Rails 8 support
- Remove compatibility patches once ViewComponent natively supports Rails 8
- Keep CI tests updated with new component requirements

## Quick Checklist for New Components
- [ ] Define all required parameters in `initialize` method
- [ ] Add component specs with instantiation tests
- [ ] Update CI tests if adding components to compatibility checks
- [ ] Test in both development and production environments
- [ ] Verify template compilation with `rake viewcomponent:precompile`