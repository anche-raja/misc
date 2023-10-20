FROM 100769305811.dkr.ecr.us-east-1.amazonaws.com/container-repository:latest
# The below line installs the hello world web page
#COPY ./index.html /usr/local/apache2/htdocs ...
ADD pet_clinic/target/spring-petclinic-3.1.0-SNAPSHOT.jar app.jar
EXPOSE 80
ENTRYPOINT ["java","-jar","-Dserver.port=80","/app.jar"]