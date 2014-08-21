#!/usr/bin/env ruby
# encoding: utf-8

require 'sushi_fabric'

class TeqcApp <  SushiFabric::SushiApp
  def initialize
    super
    @name = 'Teqc'
    @params['process_mode'] = 'DATASET'
    @analysis_category = 'QC'
    @required_columns = ['Name','BAM','BAI', 'build']
    @required_params = ['name', 'paired']
    @params['cores'] = '4'
    @params['ram'] = '100'
    @params['scratch'] = '100'
    @params['paired'] = false
    @params['name'] = 'TEQC_Result'
    @params['designFile'] = '/srv/GT/databases/targetEnrichment_designs/SureSelect_HumanAllExon_V5_UTR/S04380219_Covered.bed'
    @params['designFile', 'description'] = 'set full path to designFile according to the used kit'
    @params['cmdOptions'] = ""
    @params['mail'] = ""
  end
 def set_default_parameters
   if dataset_has_column?('paired')
      @params['paired'] = @dataset[0]['paired']
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
    command<<  "source('/usr/local/ngseq/opt/sushi_scripts/init.R')\n"
    command << "config = list()\n"
    config = @params
    config.keys.each do |key|
      command << "config[['#{key}']] = '#{config[key]}'\n" 
    end
    command << "config[['dataRoot']] = '#{@gstore_dir}'\n"
    command << "output = list()\n"
    output = next_dataset
    output.keys.each do |key|
      command << "output[['#{key}']] = '#{output[key]}'\n" 
    end
    command<<  "inputDatasetFile = '#{@input_dataset_tsv_path}'\n"
    command<<  "teqcAPP(inputDatasetFile=inputDatasetFile, output=output, config=config)\n"
    command<<  "EOT\n"
    command
  end
end


if __FILE__ == $0
  usecase = TeqcApp.new

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

