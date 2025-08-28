# WickedPDF Configuration
WickedPdf.config = {
  # Path to the wkhtmltopdf executable
  exe_path: Gem.bin_path('wkhtmltopdf-binary', 'wkhtmltopdf'),
  
  # Layout settings
  layout: 'pdf',
  
  # Default options for all PDFs
  default_options: {
    page_size: 'A4',
    orientation: 'portrait',
    margin: {
      top: 10,
      bottom: 10,
      left: 10,
      right: 10
    },
    enable_local_file_access: true,
    encoding: 'utf-8',
    javascript_delay: 1000,
    footer: {
      right: '[page] of [topage]',
      font_size: 9
    }
  }
}