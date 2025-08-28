require 'rails_helper'

RSpec.describe CodeExecutor, type: :service do
  let(:analysis_request) { create(:analysis_request) }
  let(:execution_step) { create(:execution_step, analysis_request: analysis_request) }
  
  describe '#execute' do
    context 'with Python code' do
      let(:executor) do
        described_class.new(
          code: "print('Hello from sandbox')\nresult = 2 + 2\nprint(f'Result: {result}')",
          language: 'python',
          execution_step: execution_step,
          datasets: {}
        )
      end
      
      it 'executes Python code safely' do
        # Skip if Docker is not available in test environment
        skip 'Docker required for this test' unless system('docker version > /dev/null 2>&1')
        
        expect(executor.execute).to be true
        execution_step.reload
        
        expect(execution_step.status).to eq('completed')
        expect(execution_step.output).to include('Hello from sandbox')
        expect(execution_step.output).to include('Result: 4')
        expect(execution_step.error_message).to be_nil
      end
      
      it 'handles Python errors gracefully' do
        skip 'Docker required for this test' unless system('docker version > /dev/null 2>&1')
        
        executor = described_class.new(
          code: "raise ValueError('Test error')",
          language: 'python',
          execution_step: execution_step,
          datasets: {}
        )
        
        executor.execute
        execution_step.reload
        
        expect(execution_step.status).to eq('completed')
        expect(execution_step.error_message).to include('ValueError: Test error')
      end
      
      it 'enforces execution timeout' do
        skip 'Docker required for this test' unless system('docker version > /dev/null 2>&1')
        
        executor = described_class.new(
          code: "import time\ntime.sleep(60)",  # Sleep longer than timeout
          language: 'python',
          execution_step: execution_step,
          datasets: {}
        )
        
        stub_const('CodeExecutor::EXECUTION_TIMEOUT', 2.seconds)
        
        executor.execute
        execution_step.reload
        
        expect(execution_step.error_message).to include('timeout')
      end
    end
    
    context 'with R code' do
      let(:executor) do
        described_class.new(
          code: "print('Hello from R')\nx <- c(1,2,3,4,5)\nmean(x)",
          language: 'r',
          execution_step: execution_step,
          datasets: {}
        )
      end
      
      it 'executes R code safely' do
        skip 'Docker required for this test' unless system('docker version > /dev/null 2>&1')
        
        expect(executor.execute).to be true
        execution_step.reload
        
        expect(execution_step.status).to eq('completed')
        expect(execution_step.output).to include('Hello from R')
        expect(execution_step.error_message).to be_nil
      end
    end
    
    context 'with data science operations' do
      it 'can load and process CSV data' do
        skip 'Docker required for this test' unless system('docker version > /dev/null 2>&1')
        
        # Create sample CSV file
        csv_path = Rails.root.join('tmp', 'test_data.csv')
        File.write(csv_path, "name,value\nA,1\nB,2\nC,3")
        
        executor = described_class.new(
          code: "import pandas as pd\nprint(df.head())\nprint(f'Mean: {df[\"value\"].mean()}')",
          language: 'python',
          execution_step: execution_step,
          datasets: { 'df' => csv_path.to_s }
        )
        
        executor.execute
        execution_step.reload
        
        expect(execution_step.output).to include('Mean: 2.0')
      ensure
        FileUtils.rm_f(csv_path) if csv_path
      end
      
      it 'can generate and save plots' do
        skip 'Docker required for this test' unless system('docker version > /dev/null 2>&1')
        
        executor = described_class.new(
          code: <<~PYTHON,
            import matplotlib.pyplot as plt
            plt.figure(figsize=(8, 6))
            plt.plot([1, 2, 3, 4], [1, 4, 2, 3])
            plt.title('Test Plot')
            plt.xlabel('X axis')
            plt.ylabel('Y axis')
          PYTHON
          language: 'python',
          execution_step: execution_step,
          datasets: {}
        )
        
        executor.execute
        execution_step.reload
        
        expect(execution_step.status).to eq('completed')
        expect(execution_step.metadata['generated_files']).to be_present
        expect(execution_step.metadata['generated_files'].first['name']).to match(/plot_\d+\.png/)
      end
    end
    
    context 'security constraints' do
      it 'prevents network access' do
        skip 'Docker required for this test' unless system('docker version > /dev/null 2>&1')
        
        executor = described_class.new(
          code: "import urllib.request\nurllib.request.urlopen('http://google.com')",
          language: 'python',
          execution_step: execution_step,
          datasets: {}
        )
        
        executor.execute
        execution_step.reload
        
        expect(execution_step.error_message).to be_present
      end
      
      it 'prevents file system access outside workspace' do
        skip 'Docker required for this test' unless system('docker version > /dev/null 2>&1')
        
        executor = described_class.new(
          code: "with open('/etc/passwd', 'r') as f: print(f.read())",
          language: 'python',
          execution_step: execution_step,
          datasets: {}
        )
        
        executor.execute
        execution_step.reload
        
        expect(execution_step.error_message).to be_present
      end
      
      it 'enforces memory limits' do
        skip 'Docker required for this test' unless system('docker version > /dev/null 2>&1')
        
        executor = described_class.new(
          code: "data = [0] * (10**9)",  # Try to allocate huge array
          language: 'python',
          execution_step: execution_step,
          datasets: {}
        )
        
        executor.execute
        execution_step.reload
        
        expect(execution_step.status).to eq('failed')
      end
    end
  end
  
  describe 'validations' do
    it 'requires code' do
      executor = described_class.new(language: 'python', execution_step: execution_step)
      expect(executor).not_to be_valid
      expect(executor.errors[:code]).to include("can't be blank")
    end
    
    it 'requires valid language' do
      executor = described_class.new(code: 'test', language: 'invalid', execution_step: execution_step)
      expect(executor).not_to be_valid
      expect(executor.errors[:language]).to include("is not included in the list")
    end
    
    it 'accepts valid languages' do
      %w[python r sql].each do |lang|
        executor = described_class.new(code: 'test', language: lang, execution_step: execution_step)
        expect(executor.errors[:language]).to be_empty
      end
    end
  end
end