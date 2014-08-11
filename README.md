This is a [Docker](http://docker.io) project for building a clean Joomla 3 machine
for development.

Actually there will be 3 machines build:

- data-store: holds the MySql data and the website itself
- site-db: a dedicated MariaDB (MySQL) machine
- web-machine: the Apache web server
- 
It got Maintained by magicmonty befor i updated it a bit so its more future profe and easyer edit able as also removed all depdencys from all this folders and so on

Converted his Dockerfile to ovmf docker file

Also Implamented Frank Lemanschik ENV DOCKER_RUN and ENV DOCKER_BUILD filds to get infos how to build a container
This enables all to act like in the ovmf standart Spezifyed you add full run command and build command into the ENV wars
SO you can place additional ENV ESX_RUN and ENV ESX_BUILD

so the image can be build in any envirment or vm

its the final stage of Compatiblity!!!! can execute ANSIBLE and all you whant on every plattform and all MODULAR
you can even add 
