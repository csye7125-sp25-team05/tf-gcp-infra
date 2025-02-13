pipeline {
    agent any
    environment {
        TF_VERSION = "1.10.5"
        TF_BINARY = "/usr/local/bin/terraform"
    }

    stages {
        stage('Checkout Code') {
            steps {
                checkout scm
            }
        }
        stage('Install Terraform') {
            steps {
                script {
                    sh """
                    # Install Terraform dynamically inside the Jenkins pipeline
                    curl -fsSL https://releases.hashicorp.com/terraform/$TF_VERSION/terraform_${TF_VERSION}_linux_amd64.zip -o terraform.zip
                    unzip terraform.zip
                    sudo mv terraform $TF_BINARY
                    rm terraform.zip
                    $TF_BINARY --version
                    """
                }
            }
        }
        
        stage('Terraform Format Check') {
            steps {
                script {
                    def dirs = ['gcp-org', 'gcp-project-demo', 'gcp-project-dev', 'gcp-project-dns', 'modules']
                    dirs.each { dir ->
                        if (fileExists(dir)) {
                            sh "terraform fmt -check -recursive ${dir}"
                        }
                    }
                }
            }
        }

        stage('Terraform Validate') {
            steps {
                script {
                    def dirs = ['gcp-org', 'gcp-project-demo', 'gcp-project-dev', 'gcp-project-dns']
                    dirs.each { dir ->
                        if (fileExists(dir)) {
                            sh """
                            echo "Validating Terraform configuration in ${dir}"
                            cd ${dir}
                            terraform init -backend=false
                            terraform validate
                            cd ..
                            """
                        }
                    }
                }
            }
        }
    }
}
