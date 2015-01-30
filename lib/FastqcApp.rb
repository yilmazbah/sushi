#!/usr/bin/env ruby
# encoding: utf-8

require 'sushi_fabric'
require_relative 'global_variables'
include GlobalVariables

class FastqcApp <  SushiFabric::SushiApp
  def initialize
    super
    @name = 'Fastqc'
    @params['process_mode'] = 'DATASET'
    @analysis_category = 'QC'
    @description =<<-EOS
A quality control tool for NGS reads<br/>
<a href='http://www.bioinformatics.babraham.ac.uk/projects/fastqc'/>Web-site with docu and a tutorial video</a>
EOS
    @required_columns = ['Name','Read1']
    @required_params = ['name', 'paired']
    @params['cores'] = '8'
    @params['ram'] = '16'
    @params['scratch'] = '100'
    @params['paired'] = false
    @params['name'] = 'FastQC_Result'
    @params['cmdOptions'] = ""
    @params['mail'] = ""
  end
 def set_default_parameters
    @params['paired'] = dataset_has_column?('Read2')
  end
  def preprocess
    if @params['paired']
      @required_columns<<  'Read2'
    end
  end
  def next_dataset
    report_file = File.join(@result_dir, @params['name'])
    report_link = File.join(report_file, '00index.html')
    {'Name'=>@params['name'],
     'Report [File]'=>report_file,
     'Html [Link]'=>report_link,
    }
  end
  def commands
    command = "/usr/local/ngseq/bin/R --vanilla --slave<<  EOT\n"
    command << "GLOBAL_VARIABLES <<- '#{GLOBAL_VARIABLES}'\n"
    command << "R_SCRIPT_DIR <<- '#{R_SCRIPT_DIR}'\n"
    command<<  "source(file.path(R_SCRIPT_DIR, 'init.R'))\n"
    command << "config = list()\n"
    config = @params
    config.keys.each do |key|
      command << "config[['#{key}']] = '#{config[key]}'\n" 
    end
    command << "config[['dataRoot']] = '#{@gstore_dir}'\n"
    command << "config[['resultDir']] = '#{@result_dir}'\n"
    command << "output = list()\n"
    output = next_dataset
    output.keys.each do |key|
      command << "output[['#{key}']] = '#{output[key]}'\n" 
    end
    command<<  "inputDatasetFile = '#{@input_dataset_tsv_path}'\n"
    command<<  "runApp('fastqcApp', input=inputDatasetFile, output=output, config=config)\n"
    command<<  "EOT\n"
    command
  end
end

if __FILE__ == $0
  usecase = FastqcApp.new

  usecase.project = "p1001"
  usecase.user = "masa"

  # set user parameter
  # for GUI sushi
  #usecase.params['process_mode'].value = 'SAMPLE'
  #usecase.params['build'] = 'TAIR10'
  #usecase.params['paired'] = true
  #usecase.params['cores'] = 2
  #usecase.params['node'] = 'fgcz-c-048'

  # also possible to load a parameterset csv file
  # mainly for CUI sushi
  usecase.parameterset_tsv_file = 'tophat_parameterset.tsv'
  #usecase.params['name'] = 'name'

  # set input dataset
  # mainly for CUI sushi
  usecase.dataset_tsv_file = 'tophat_dataset.tsv'

  # also possible to load a input dataset from Sushi DB
  #usecase.dataset_sushi_id = 1

  # run (submit to workflow_manager)
  usecase.run
  #usecase.test_run

end

