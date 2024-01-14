library(dplyr)
library(sf)
library(rvest)
library(rjson)

# 擷取所有路線表
url="https://ebus.gov.taipei/ebus"
html_content=read_html(url)
all_route=html_nodes(html_content, "#list a")
all_route=data.frame(UniRouteId=gsub("javascript:go\\(|\\)|'", "", html_attr(all_route, 'href')),
                     UniRouteName=gsub(" ", "", html_text(all_route)))


# 逐一擷取路線與站點
bus_route_all=data.frame()
bus_stop_all=data.frame()
bus_shape_all=data.frame()

for(i in c(1:length(all_route$UniRouteId))){
  url=paste0("https://ebus.gov.taipei/Route/StopsOfRoute?routeid=", all_route$UniRouteId[i])
  html_content=read_html(url)
  html_content=html_nodes(html_content, "script")
  html_content=html_content[grepl("routeJsonString", html_content)]
  html_content=strsplit(as.character(html_content), "\n")[[1]]
  html_content=html_content[grepl("routeJsonString", html_content)]
  html_content=strsplit(as.character(html_content), ";\\r")[[1]]
  html_content=as.character(html_content[grepl("stringify", html_content)])
  html_content=substr(html_content, regexpr("stringify", html_content)+10, max(which(strsplit(html_content, "")[[1]]=="}")))
  html_content=rjson::fromJSON(html_content)
  
  # Bus Route
  bus_route=data.frame(html_content[c("UniRouteId","Name","BeginStop","LastStop","TicketPrice","BusTimeDesc","HeadwayDesc","HolidayBusTimeDesc","HolidayHeadwayDesc","SegmentBuffer","orgphone")])%>%
    rename(UniRouteName=Name)
  
  # Bus Stop
  temp1=data.frame(UniRouteId=bus_route$UniRouteId,
                   UniRouteName=bus_route$UniRouteName,
                   UniStopId=mapply(function(x) html_content$GoDirStops[[x]]$UniStopId, c(1:length(html_content$GoDirStops))),
                   UniStopName=mapply(function(x) html_content$GoDirStops[[x]]$Name, c(1:length(html_content$GoDirStops))),
                   Longitude=mapply(function(x) html_content$GoDirStops[[x]]$Longitude, c(1:length(html_content$GoDirStops))),
                   Latitude=mapply(function(x) html_content$GoDirStops[[x]]$Latitude, c(1:length(html_content$GoDirStops))),
                   Direction=1,
                   StopSequence=c(1:length(html_content$GoDirStops)))
  if(!is.null(html_content$BackDirStops)){
    temp2=data.frame(UniRouteId=bus_route$UniRouteId,
                     UniRouteName=bus_route$UniRouteName,
                     UniStopId=mapply(function(x) html_content$BackDirStops[[x]]$UniStopId, c(1:length(html_content$BackDirStops))),
                     UniStopName=mapply(function(x) html_content$BackDirStops[[x]]$Name, c(1:length(html_content$BackDirStops))),
                     Longitude=mapply(function(x) html_content$BackDirStops[[x]]$Longitude, c(1:length(html_content$BackDirStops))),
                     Latitude=mapply(function(x) html_content$BackDirStops[[x]]$Latitude, c(1:length(html_content$BackDirStops))),
                     Direction=2,
                     StopSequence=c(1:length(html_content$BackDirStops)))
    bus_stop=rbind(temp1, temp2)
  }else{
    bus_stop=temp1
  }
  
  # Bus Shape
  bus_shape=data.frame(UniRouteId=bus_route$UniRouteId,
                       UniRouteName=bus_route$UniRouteName,
                       WKT=c("wkt","wkt0","wkt1"),
                       geometry=c(ifelse(is.null(html_content$wkt), NA, html_content$wkt),
                                  ifelse(is.null(html_content$wkt0), NA, html_content$wkt0),
                                  ifelse(is.null(html_content$wkt1), NA, html_content$wkt1)))
  
  bus_route_all=rbind(bus_route_all, bus_route)
  bus_stop_all=rbind(bus_stop_all, bus_stop)
  bus_shape_all=rbind(bus_shape_all, bus_shape)
  print(i)
}
