pipeline {
    agent any

    stages {
        stage('System Information') {
            steps {
                sh '''
                echo "========================================="
                echo "        Jenkins Pipeline Test"
                echo "========================================="

                echo "Job Name      : $JOB_NAME"
                echo "Build Number  : $BUILD_NUMBER"
                echo "Node Name     : $NODE_NAME"

                echo "Hostname      : $(hostname)"

                PRIVATE_IP=$(hostname -I | awk '{print $1}')
                echo "Private IP    : $PRIVATE_IP"

                # Get IMDSv2 Token
                TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
                    -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")

                PUBLIC_IP=$(curl -s \
                    -H "X-aws-ec2-metadata-token: $TOKEN" \
                    http://169.254.169.254/latest/meta-data/public-ipv4)

                if [ -z "$PUBLIC_IP" ]; then
                    PUBLIC_IP="No Public IP"
                fi

                echo "Public IP     : $PUBLIC_IP"

                echo "Date          : $(date)"

                echo "========================================="
                '''
            }
        }
    }
}