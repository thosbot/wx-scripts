#!/bin/bash

lat=39.933656012323574
lon=-75.15672326764346
key=1506d768b9c2dd3d859f8afa4a9be239
not="current,minutely,hourly"

url="https://api.openweathermap.org/data/2.5/onecall?lat=$lat&lon=$lon&exclude=$not&appid=$key"
echo "$url"
curl -i "$url"
