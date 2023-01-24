FROM --platform=linux/amd64 amazonlinux:2

# Add the Amazon Corretto repository
RUN rpm --import https://yum.corretto.aws/corretto.key
RUN curl -L -o /etc/yum.repos.d/corretto.repo https://yum.corretto.aws/corretto.repo

# Update the packages and install Amazon Corretto 17, Maven and Zip
RUN yum -y update
RUN yum install -y java-17-amazon-corretto-jmods maven zip

# Set Java 17 as the default
RUN update-alternatives --set java "/usr/lib/jvm/java-17-amazon-corretto.x86_64/bin/java"
RUN update-alternatives --set javac "/usr/lib/jvm/java-17-amazon-corretto.x86_64/bin/javac"

# Copy the software folder to the image and build the function
COPY function function
WORKDIR /function
RUN mvn clean package

# Find JDK module dependencies dynamically from the uber jar
RUN jdeps -q \
    --ignore-missing-deps \
    --multi-release 17 \
    --print-module-deps \
    target/function.jar > jre-deps.info

# Create a slim Java 17 JRE which only contains the required modules to run the function
RUN jlink --verbose \
    --compress 2 \
    --strip-java-debug-attributes \
    --no-header-files \
    --no-man-pages \
    --output /jre17-slim \
    --add-modules $(cat jre-deps.info)

# Use Java's Application Class Data Sharing feature
# It creates the file /jre17-slim/lib/server/classes.jsa
RUN /jre17-slim/bin/java -Xshare:dump

# Package everything together into a custom runtime archive
# Package everything together into a custom runtime archive
WORKDIR /
COPY bootstrap bootstrap
RUN chmod 755 bootstrap
RUN cp function/target/function.jar function.jar
RUN zip -r runtime.zip \
    bootstrap \
    function.jar \
    /jre17-slim
