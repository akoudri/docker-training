FROM jenkins/inbound-agent

USER root
RUN apt-get update && apt-get install -y docker.io maven git
RUN usermod -aG docker jenkins
USER jenkins