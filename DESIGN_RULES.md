# Design Rules & Guidelines

This document outlines the design principles, spacing methodology, and component patterns used in the Connectica platform to ensure consistency and maintainability.

## Design Philosophy

### Core Principles
1. **Mobile-First Responsive Design** - Design for smallest screen first, then enhance
2. **Accessibility by Default** - Semantic HTML, proper contrast, keyboard navigation
3. **Component-Driven Architecture** - Reusable ViewComponents with consistent patterns
4. **Progressive Enhancement** - Base functionality works without JavaScript
5. **Performance-Conscious** - Optimize for speed and minimal resource usage

### Visual Hierarchy
- **Primary Actions**: Blue gradients (`from-blue-600 to-blue-700`)
- **Secondary Actions**: Green gradients (`from-green-600 to-green-700`)
- **Neutral Actions**: Gray variants with proper contrast
- **Destructive Actions**: Red variants (when needed)

## Spacing System

### Vertical Spacing (Sections)
```css
/* Large sections (hero, major content blocks) */
py-12     /* 48px top/bottom - standard section spacing */
py-16     /* 64px top/bottom - only for hero sections or major separators */

/* Medium sections (subsections, cards) */
py-8      /* 32px top/bottom - subsection spacing */
py-6      /* 24px top/bottom - card internal padding */

/* Small spacing (elements, components) */
py-4      /* 16px top/bottom - compact elements */
py-3      /* 12px top/bottom - tight spacing */
```

### Margin System
```css
/* Section margins */
mb-8      /* 32px - standard section bottom margin */
mb-6      /* 24px - subsection margin */
mb-4      /* 16px - component margin */
mb-3      /* 12px - tight component margin */
mb-2      /* 8px - element margin */

/* Never use mb-12 or larger for standard content flow */
```

### Gap System (Grids & Flex)
```css
gap-6     /* 24px - standard grid/flex gap */
gap-4     /* 16px - compact grid gap */
gap-8     /* 32px - only for large feature cards */
```

## Typography Scale

### Headings
```css
/* Page titles */
text-4xl md:text-6xl font-extrabold    /* Hero titles */
text-3xl md:text-4xl font-bold         /* Page titles */

/* Section headings */
text-2xl md:text-3xl font-bold         /* Major section titles */
text-xl md:text-2xl font-semibold      /* Subsection titles */

/* Component headings */
text-lg font-semibold                  /* Card titles */
text-base font-semibold                /* Small component titles */
```

### Body Text
```css
/* Primary content */
text-lg leading-relaxed                /* Large body text */
text-base leading-relaxed              /* Standard body text */
text-sm leading-relaxed                /* Secondary text */

/* Supporting text */
text-xs font-medium uppercase tracking-wide  /* Labels */
text-sm text-gray-600 dark:text-gray-400     /* Descriptions */
```

## Responsive Grid System

### Breakpoint Strategy
```css
/* Always start mobile-first */
grid-cols-1                            /* Mobile (< 640px) */
sm:grid-cols-2                         /* Small (≥ 640px) */
md:grid-cols-3                         /* Medium (≥ 768px) */
lg:grid-cols-4                         /* Large (≥ 1024px) */
xl:grid-cols-5                         /* Extra large (≥ 1280px) - rarely used */

/* Feature cards (larger elements) */
grid-cols-1 lg:grid-cols-2             /* Single column on mobile, two on large screens */

/* Stats/metrics */
grid-cols-2 lg:grid-cols-4             /* Two on mobile, four on large screens */
```

### Container Widths
```css
max-w-7xl mx-auto px-4 sm:px-6 lg:px-8   /* Standard page container */
max-w-4xl mx-auto                         /* Content containers */
max-w-2xl mx-auto                         /* Text content (descriptions) */
```

## Component Patterns

### Card Components (Flowbite Standard)
```css
/* Base card structure */
.card-base {
  @apply p-6 bg-white border border-gray-200 rounded-xl shadow-sm 
         dark:bg-gray-800 dark:border-gray-700;
}

/* Interactive cards */
.card-interactive {
  @apply hover:shadow-md hover:border-gray-200 dark:hover:border-gray-600 
         transition-all duration-200;
}

/* Feature cards (larger) */
.card-feature {
  @apply p-8 bg-white border border-gray-200 rounded-2xl shadow-sm 
         dark:bg-gray-800 dark:border-gray-700 
         hover:shadow-xl hover:-translate-y-1 transition-all duration-300;
}
```

### Icon Containers
```css
/* Standard icon containers */
w-12 h-12 rounded-xl                      /* Standard size for capability icons */
w-16 h-16 rounded-xl                      /* Large size for feature icons */

/* Icon sizes within containers */
w-6 h-6                                   /* Icons in standard containers */
w-8 h-8                                   /* Icons in large containers */
```

### Button Patterns
```css
/* Primary buttons */
.btn-primary {
  @apply inline-flex items-center justify-center px-6 py-3 text-base font-medium 
         text-white bg-gradient-to-r from-blue-600 to-blue-700 
         hover:from-blue-700 hover:to-blue-800 rounded-lg 
         focus:ring-4 focus:ring-blue-300 focus:ring-opacity-50 
         transition-all duration-200 hover:shadow-lg transform hover:-translate-y-0.5;
}

/* Secondary buttons */
.btn-secondary {
  @apply text-gray-900 bg-white border border-gray-300 hover:bg-gray-100 
         focus:ring-4 focus:ring-gray-200 font-medium rounded-lg text-sm px-5 py-2.5 
         dark:bg-gray-800 dark:text-white dark:border-gray-600 
         dark:hover:bg-gray-700 dark:hover:border-gray-600 dark:focus:ring-gray-700;
}
```

## Color System

### Semantic Colors
```css
/* Primary Brand */
Blue: #3B82F6 (blue-500) to #2563EB (blue-600)

/* Success/Positive */
Green: #10B981 (green-500) to #059669 (green-600)

/* Warning/Attention */
Orange: #F59E0B (orange-500) to #D97706 (orange-600)

/* Secondary/Alternative */
Purple: #8B5CF6 (purple-500) to #7C3AED (purple-600)
```

### Text Colors
```css
/* Light mode */
text-gray-900                             /* Primary text */
text-gray-600                             /* Secondary text */
text-gray-500                             /* Tertiary text */

/* Dark mode */
dark:text-white                           /* Primary text */
dark:text-gray-300                        /* Secondary text */
dark:text-gray-400                        /* Tertiary text */
```

## Animation & Transitions

### Standard Transitions
```css
transition-all duration-200               /* Fast interactions (hover, focus) */
transition-all duration-300               /* Medium animations (cards, modals) */
transition-transform duration-200         /* Transform-only animations */
```

### Hover Effects
```css
/* Cards */
hover:shadow-md                           /* Subtle shadow increase */
hover:shadow-xl                           /* Significant shadow for feature cards */
hover:-translate-y-1                      /* Subtle lift for feature cards */
hover:scale-105                           /* Slight scale for icons */

/* Buttons */
hover:shadow-lg transform hover:-translate-y-0.5  /* Button lift effect */
```

## Accessibility Requirements

### Color Contrast
- Minimum 4.5:1 ratio for normal text
- Minimum 3:1 ratio for large text
- All interactive elements must have visible focus states

### Focus Management
```css
focus:ring-4 focus:ring-{color}-300 focus:ring-opacity-50
```

### Semantic HTML
- Use proper heading hierarchy (h1 → h2 → h3)
- Include `alt` attributes for all images
- Use `aria-label` for icon-only buttons
- Maintain logical tab order

## ViewComponent Architecture

### Component Naming
- Components end with `Component` (e.g., `HomepageHeroComponent`)
- Template files match component names
- Use semantic component names that describe purpose, not appearance

### Component Structure
```ruby
class ComponentNameComponent < ViewComponent::Base
  def initialize(required_param:, optional_param: nil)
    @required_param = required_param
    @optional_param = optional_param
  end

  private

  attr_reader :required_param, :optional_param

  # Helper methods for styling logic
  def css_classes
    # Dynamic CSS class generation
  end
end
```

### Props Pattern
- Always validate required parameters
- Provide sensible defaults for optional parameters
- Use keyword arguments for clarity
- Keep component interfaces simple and focused

## Performance Guidelines

### CSS Organization
- Use Tailwind utility classes primarily
- Extract common patterns to component CSS only when necessary
- Avoid inline styles
- Optimize for minimal CSS bundle size

### Image Optimization
- Use appropriate image formats (WebP where supported)
- Implement lazy loading for below-fold images
- Provide proper alt text for accessibility
- Use responsive images with `srcset` when needed

## Testing Considerations

### Visual Regression
- Test components in isolation
- Verify responsive behavior at multiple breakpoints
- Test dark mode variants
- Validate accessibility compliance

### Browser Support
- Modern browsers (last 2 versions)
- Mobile Safari and Chrome
- Graceful degradation for older browsers

---

## Implementation Checklist

When implementing new components or pages:

- [ ] Follow mobile-first responsive design
- [ ] Use established spacing system
- [ ] Implement proper dark mode support
- [ ] Add appropriate hover and focus states
- [ ] Test accessibility (contrast, keyboard navigation)
- [ ] Validate across different screen sizes
- [ ] Use semantic HTML structure
- [ ] Follow ViewComponent architecture patterns
- [ ] Document any new patterns or exceptions

---

*Last updated: 2024-12-25*
*This document should be updated when new patterns or standards are established.*