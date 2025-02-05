pipeline {
    agent { label 'ubuntu' } // Runs on an Ubuntu agent

    triggers {
        githubPullRequests() // Trigger on PR events
    }

    environment {
        TERRAFORM_VERSION = "1.4.6" // Set Terraform version
    }

    stages {
        stage('Checkout Code') {
            steps {
                checkout scm
            }
        }

        stage('Setup Terraform') {
            steps {
                sh "terraform --version"
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
