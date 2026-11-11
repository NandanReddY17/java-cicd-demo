// Jenkins CI/CD pipeline: GitHub -> Maven -> Docker -> (GitHub Container Registry -> Azure AKS via Ansible)
// The cloud stages run only when the Jenkins global env var CLOUD_DEPLOY is "true" and these
// credentials exist in Jenkins:
//   ghcr-creds  Username with password: GitHub username + personal access token (write:packages)
//   kubeconfig  Secret file: kubeconfig of the CI service account (infra/azure/setup-aks.sh)
pipeline {
    agent any

    options {
        timestamps()
        disableConcurrentBuilds()          // never two deployments at once
        buildDiscarder(logRotator(numToKeepStr: '20'))
    }

    triggers {
        // Jenkins runs on a local PC that GitHub cannot reach, so it polls GitHub
        // every minute instead of waiting for a webhook.
        pollSCM('* * * * *')
    }

    environment {
        REGISTRY_REPO = 'ghcr.io/nandanreddy17/java-cicd-demo'   // registry names must be lowercase
        APP_NAME      = 'java-cicd-demo'
    }

    stages {
        stage('Checkout') {
            steps {
                // The build network intermittently drops TLS connections to GitHub, so retry.
                retry(3) {
                    checkout scm
                }
                script {
                    env.GIT_SHA = sh(script: 'git rev-parse --short=7 HEAD', returnStdout: true).trim()
                    env.LOCAL_IMAGE = "${env.APP_NAME}:${env.GIT_SHA}"
                }
                echo "Building commit ${env.GIT_SHA}"
            }
        }

        stage('Secret Scan (Gitleaks)') {
            // Scans the whole Git history for passwords, API keys, tokens and private keys.
            // A finding exits with code 1 and stops the pipeline before anything is built.
            // The workspace lives in the jenkins_home volume, mounted read-only into Gitleaks.
            steps {
                sh '''
                    docker run --rm -v jenkins_jenkins_home:/var/jenkins_home:ro \
                      zricethezav/gitleaks:v8.30.1 git "$WORKSPACE" --redact --verbose
                '''
            }
        }

        stage('Compile') {
            steps {
                sh 'mvn -B compile'
            }
        }

        stage('Unit Tests') {
            steps {
                sh 'mvn -B test'
            }
            post {
                always {
                    junit 'target/surefire-reports/*.xml'
                }
            }
        }

        stage('Package') {
            steps {
                sh 'mvn -B -DskipTests package'
                archiveArtifacts artifacts: 'target/java-cicd-demo.jar', fingerprint: true
            }
        }

        stage('Docker Build') {
            steps {
                sh 'docker build -t "$LOCAL_IMAGE" -t "$APP_NAME:latest" .'
            }
        }

        stage('Container Smoke Test') {
            // Start the new image and call it over HTTP before it goes anywhere near the cluster.
            steps {
                sh '''
                    NET="smoke-$BUILD_NUMBER"
                    docker network create "$NET" >/dev/null
                    docker run -d --name "smoke-$BUILD_NUMBER" --network "$NET" \
                      -e APP_BUILD="$GIT_SHA" "$LOCAL_IMAGE" >/dev/null
                    for i in $(seq 1 30); do
                      if docker run --rm --network "$NET" curlimages/curl:8.11.1 -sf \
                           "http://smoke-$BUILD_NUMBER:8080/actuator/health/readiness" >/dev/null 2>&1; then
                        break
                      fi
                      sleep 2
                    done
                    docker run --rm --network "$NET" curlimages/curl:8.11.1 -sf \
                      "http://smoke-$BUILD_NUMBER:8080/api/calculate?a=6&b=7&op=multiply" | tee smoke.json
                    grep -q '"result":42.0' smoke.json
                    docker run --rm --network "$NET" curlimages/curl:8.11.1 -sf \
                      "http://smoke-$BUILD_NUMBER:8080/api/info" | grep -q "\\"build\\":\\"$GIT_SHA\\""
                    echo "Smoke test passed"
                '''
            }
            post {
                always {
                    sh 'docker rm -f "smoke-$BUILD_NUMBER" >/dev/null 2>&1 || true; docker network rm "smoke-$BUILD_NUMBER" >/dev/null 2>&1 || true'
                }
            }
        }

        stage('Push to GHCR') {
            when { environment name: 'CLOUD_DEPLOY', value: 'true' }
            steps {
                withCredentials([usernamePassword(credentialsId: 'ghcr-creds',
                        usernameVariable: 'GHCR_USER', passwordVariable: 'GHCR_TOKEN')]) {
                    sh '''
                        set +x
                        echo "$GHCR_TOKEN" | docker login ghcr.io -u "$GHCR_USER" --password-stdin
                        docker tag "$LOCAL_IMAGE" "$REGISTRY_REPO:$GIT_SHA"
                        docker tag "$LOCAL_IMAGE" "$REGISTRY_REPO:latest"
                        docker push "$REGISTRY_REPO:$GIT_SHA"
                        docker push "$REGISTRY_REPO:latest"
                        docker logout ghcr.io
                    '''
                }
            }
        }

        stage('Deploy to AKS (Ansible)') {
            when { environment name: 'CLOUD_DEPLOY', value: 'true' }
            steps {
                withCredentials([file(credentialsId: 'kubeconfig', variable: 'KUBECONFIG')]) {
                    sh '''
                        ansible-playbook -i ansible/inventory.ini ansible/deploy.yml \
                          -e image="$REGISTRY_REPO:$GIT_SHA" -e build="$GIT_SHA"
                    '''
                }
            }
        }

        stage('Verify Deployment') {
            when { environment name: 'CLOUD_DEPLOY', value: 'true' }
            steps {
                withCredentials([file(credentialsId: 'kubeconfig', variable: 'KUBECONFIG')]) {
                    sh '''
                        kubectl get deployment "$APP_NAME"
                        kubectl get pods -l app="$APP_NAME" -o wide
                        kubectl get service "$APP_NAME"
                        kubectl rollout history deployment/"$APP_NAME"
                    '''
                }
            }
        }
    }

    post {
        success {
            echo "Pipeline succeeded for commit ${env.GIT_SHA}"
        }
        failure {
            echo 'Pipeline failed. Check the red stage in the Stage View for details.'
        }
    }
}
