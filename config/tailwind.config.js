module.exports = {
  darkMode: 'class', // Enable class-based dark mode
  content: [
    './public/*.html',
    './app/helpers/**/*.rb',
    './app/javascript/**/*.js',
    './app/views/**/*.{erb,haml,html,slim}'
  ],
  theme: {
    extend: {
      colors: {
        dark: {
          bg: {
            primary: '#111827',
            secondary: '#1f2937',
            tertiary: '#374151'
          },
          text: {
            primary: '#f9fafb',
            secondary: '#9ca3af',
            tertiary: '#6b7280'
          }
        }
      }
    },
  },
  plugins: [
    require('@tailwindcss/forms'),
    require('@tailwindcss/typography'),
    require('@tailwindcss/container-queries'),
  ]
}