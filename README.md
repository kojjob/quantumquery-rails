# QuantumQuery - Natural Language Data Science Platform

Rails 8.0.1 application that democratizes data analysis by allowing users to ask questions in plain English and get advanced analytics powered by multiple AI models.

## 🚀 Features

- **Multi-Model AI Support**: Intelligent routing between Claude 3 (Opus/Sonnet/Haiku), GPT-4, Gemini, Llama 3, Mixtral, and more
- **Rails 8 with Solid Stack**: Using Solid Queue, Solid Cable, and Solid Cache (No Redis/Sidekiq required!)
- **Natural Language Processing**: Convert English questions into executable code
- **Sandboxed Execution**: Secure Docker containers for Python/R/SQL code execution
- **Multi-Tier Subscriptions**: Free, Professional, Enterprise tiers with different AI model access
- **Smart Model Selection**: Automatic selection based on task complexity and cost optimization

## 📋 Requirements

* Ruby 3.3.6
* Rails 8.0.1
* PostgreSQL 14+
* Docker (for code execution sandboxing)

## 🛠️ Installation

```bash
# Clone the repository
git clone https://github.com/kojjob/quantumquery-rails.git
cd quantumquery-rails

# Install dependencies
bundle install

# Setup database
rails db:create
rails db:migrate
rails db:seed

# Start the server
rails server
```

## 🏗️ Architecture

### Core Models
- `User` - Multi-tier subscription management
- `Organization` - Team collaboration and billing
- `Dataset` - Data source connections (PostgreSQL, MySQL, CSV, APIs)
- `AnalysisRequest` - Natural language query processing with AASM state machine
- `ExecutionStep` - Code generation and execution tracking

### AI Provider Architecture
- Base provider abstraction for consistent interface
- Provider implementations: Anthropic, OpenAI, Google, Cohere, Replicate
- Intelligent model selection based on task type and complexity
- Fallback mechanisms for high availability

### Query Processing Pipeline
1. **Intent Analysis** - Understand what the user is asking
2. **Data Requirements** - Determine needed data sources
3. **Code Generation** - Create Python/R/SQL code
4. **Execution** - Run in sandboxed Docker container
5. **Result Interpretation** - Explain results in plain English

## 🔧 Configuration

### Environment Variables
```bash
# Database
DATABASE_URL=postgresql://user:pass@localhost/quantumquery

# AI Provider API Keys
ANTHROPIC_API_KEY=your_key
OPENAI_API_KEY=your_key
GOOGLE_AI_API_KEY=your_key
COHERE_API_KEY=your_key
REPLICATE_API_TOKEN=your_key

# Application
RAILS_MASTER_KEY=your_master_key
```

## 🧪 Testing

```bash
# Run all tests
rails test

# Run specific test file
rails test test/models/analysis_request_test.rb
```

## 🚢 Deployment

Using Rails 8's built-in Kamal for deployment:

```bash
# Setup deployment
kamal setup

# Deploy
kamal deploy
```

## 📝 License

Proprietary - All rights reserved

## 🤝 Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📧 Contact

For questions or support, please open an issue on GitHub.

---

**Repository**: https://github.com/kojjob/quantumquery-rails