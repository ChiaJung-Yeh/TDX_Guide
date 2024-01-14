library(dplyr)
library(sf)
library(TDX)
library(cli)

client_id="client_id"
client_secret="client_secret"
access_token=get_token(client_id, client_secret)

# 擷取公車路線、站牌資料
bus_route=Bus_Route(access_token, "Keelung")
bus_shape=Bus_Shape(access_token, "Keelung", dtype="sf")%>%
  st_transform(crs=3826)
bus_stop=Bus_StopOfRoute(access_token, "Keelung", dtype="sf")%>%
  st_transform(crs=3826)


# 計算站點與候選點間距離並給定標籤(只篩選小於30公尺者)
min_ret=function(x, y){
  Dist=x[x<30]
  Seq=which(x<30)
  
  if(length(Dist)==0){
    Dist=min(x)
    Seq=which.min(x)
  }
  return(list(Dist=Dist, Seq=Seq))
}


bus_stop_rev=data.frame()
cli_progress_bar(format = "Processing {pb_bar} {pb_percent} [{pb_eta}]  {.emph SubRouteUID: {bus_route$SubRouteUID[pb_current]}}", 
                 total=nrow(bus_route))

for(route in c(1:nrow(bus_route))){
  cli_progress_update()
  
  bus_shape_temp=filter(bus_shape, SubRouteUID==bus_route$SubRouteUID[route])
  bus_stop_temp=filter(bus_stop, SubRouteUID==bus_route$SubRouteUID[route], Direction==bus_route$Direction[route])
  
  if(nrow(bus_shape_temp)==0){
    bus_shape_temp=filter(bus_shape, RouteUID==bus_route$RouteUID[route], is.na(SubRouteUID))
  }
  
  # 拆分公車路線之線段
  bus_shape_coord=data.frame(st_coordinates(bus_shape_temp)[, c(1:2)])%>%
    mutate(geometry=st_as_sfc(paste0("POINT(", X, " ", Y, ")")))%>%
    st_sf(crs=3826)
  dist_point=as.numeric(st_distance(bus_shape_coord[1:(nrow(bus_shape_coord)-1),], bus_shape_coord[2:(nrow(bus_shape_coord)),], by_element=T))
  
  # 將各路段細分為至多每10公尺一段(使配對更為精確)
  all_point=data.frame()
  for(i in c(1:nrow(bus_shape_coord))){
    if(i!=nrow(bus_shape_coord)){
      new_int_num=ceiling(dist_point[i]/10)
      if(new_int_num>1){
        new_point=data.frame(X=mapply(function(x) bus_shape_coord$X[i]+((bus_shape_coord$X[i+1]-bus_shape_coord$X[i])/new_int_num)*x, c(1:(new_int_num-1))),
                             Y=mapply(function(x) bus_shape_coord$Y[i]+((bus_shape_coord$Y[i+1]-bus_shape_coord$Y[i])/new_int_num)*x, c(1:(new_int_num-1))))
        temp_point=rbind(data.frame(X=bus_shape_coord$X[i], Y=bus_shape_coord$Y[i]), new_point)
        all_point=rbind(all_point, temp_point)
      }else{
        all_point=rbind(all_point, data.frame(X=bus_shape_coord$X[i], Y=bus_shape_coord$Y[i]))
      }
    }else{
      all_point=rbind(all_point, data.frame(X=bus_shape_coord$X[i], Y=bus_shape_coord$Y[i]))
    }
  }
  all_point=mutate(all_point, geometry=st_as_sfc(paste0("POINT(", X, " ", Y, ")")))%>%
    st_sf(crs=3826)
  
  # 計算各點之間的距離與累積里程
  dist_point=as.numeric(st_distance(all_point[1:(nrow(all_point)-1),], all_point[2:(nrow(all_point)),], by_element=T))
  all_point$Dist_Cum=c(0, mapply(function(x) sum(dist_point[1:x]), c(1:length(dist_point))))
  
  # 計算原始公車站牌圖資與細分點間的距離關係
  all_dist=as.matrix(st_distance(bus_stop_temp, all_point))
  all_dist_poss=apply(all_dist, 1, min_ret)
  
  # 演算法尋找最可能匹配點位(類似Hidden Markov Model)
  all_seq=c()
  step_seq=0
  for(m in c(1:length(all_dist_poss))){
    emis_prob=abs(1/all_dist_poss[[m]]$Dist)
    trans_prob=1/(all_dist_poss[[m]]$Seq-step_seq)
    step_seq=all_dist_poss[[m]]$Seq[which.max(emis_prob*trans_prob)]
    all_seq=c(all_seq, step_seq)
  }
  
  # 將匹配點位貼附於原始公車資料中
  bus_stop_temp_rev=cbind(st_drop_geometry(bus_stop_temp), all_point[all_seq,])%>%
    st_sf(crs=3826)
  
  # 透過累積里程計算兩站點間距離
  bus_stop_temp_rev$Dist_Intv=c(NA, bus_stop_temp_rev$Dist_Cum[c(2:nrow(bus_stop_temp_rev))]-bus_stop_temp_rev$Dist_Cum[c(1:nrow(bus_stop_temp_rev)-1)])
  
  if(sum(bus_stop_temp_rev$Dist_Intv<0, na.rm=T)!=0){
    cli_alert_info(paste0("因 TDX 路線數化有問題，SubRouteUID:", bus_route$SubRouteUID[route], "（Direction:", bus_route$Direction[route], "）部分計算結果可能有誤!"))
  }
  
  bus_stop_rev=rbind(bus_stop_rev, bus_stop_temp_rev)
}
cli_progress_done()

write.csv(st_drop_geometry(bus_stop_rev), "./Keelung Revised Bus Stop.csv", row.names=F)


