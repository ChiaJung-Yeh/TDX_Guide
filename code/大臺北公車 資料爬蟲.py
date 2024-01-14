import pandas as pd
import numpy as np
import geopandas as gpd
from shapely import wkt
import requests
from bs4 import BeautifulSoup
import json
import re
from tqdm import tqdm


# 擷取所有路線表
res=requests.get('https://ebus.gov.taipei/ebus')
res=BeautifulSoup(res.text, "html.parser")
res=res.find_all("section", class_="busline")
res=BeautifulSoup(str(res))
res=res.find_all('a')

routeid=[]
routename=[]
for route in res:
    routeid.append(re.sub("javascript:go\\(|\\)|'", '', route.get("href")))
    routename.append(re.sub(' ', '', route.get_text()))

all_route=pd.DataFrame({'UniRouteId':routeid, 'UniRouteName':routename})    
all_route=all_route.drop_duplicates().reset_index(drop=True)



# 逐一擷取路線與站點
bus_route_all=pd.DataFrame()
bus_stop_all=pd.DataFrame()
bus_shape_all=pd.DataFrame()

for i in tqdm(range(len(all_route))):
    res=requests.get('https://ebus.gov.taipei/Route/StopsOfRoute?routeid='+all_route.UniRouteId[i])
    res=BeautifulSoup(res.text, "html.parser")
    res=res.find_all("script")
    res=str(list(compress(res, [bool(re.search("routeJsonString", str(x))) for x in res])))
    res=res.split('\n')
    res=str(list(compress(res, [bool(re.search("routeJsonString", x)) for x in res])))
    res=res.split(';\\r')
    res=str(list(compress(res, [bool(re.search("stringify", x)) for x in res])))
    res=res[(re.search("stringify", res).span()[1]+1):(res.rfind('}')+1)]
    res=json.loads(res)

    # Bus Stop
    temp1=pd.DataFrame(res['GoDirStops']).loc[:,['UniStopId','Name','Longitude','Latitude']].rename(columns={'Name':'UniStopName'})
    temp1['Direction']=1
    temp1['StopSequence']=list(range(1, len(temp1)+1))
    
    if res['BackDirStops'] is not None:
        temp2=pd.DataFrame(res['BackDirStops']).loc[:,['UniStopId','Name','Longitude','Latitude']].rename(columns={'Name':'UniStopName'})
        temp2['Direction']=2
        temp2['StopSequence']=list(range(1, len(temp2)+1))
        bus_stop=pd.concat([temp1, temp2]).reset_index(drop=True)
    else:
        bus_stop=temp1
    
    # Bus Route
    bus_route=pd.DataFrame({'UniRouteId':[res['UniRouteId']],
                            'UniRouteName':[res['Name']],
                            'BeginStop':[res['BeginStop']],
                            'LastStop':[res['LastStop']],
                            'TicketPrice':res['TicketPrice'],
                            'BusTimeDesc':res['BusTimeDesc'],
                            'HeadwayDesc':res['HeadwayDesc'],
                            'HolidayBusTimeDesc':res['HolidayBusTimeDesc'],
                            'HolidayHeadwayDesc':res['HolidayHeadwayDesc'],
                            'SegmentBuffer':res['SegmentBuffer'],
                            'orgphone':res['orgphone']})
    bus_stop=pd.concat([bus_route.loc[np.repeat(0, len(bus_stop)), ['UniRouteId','UniRouteName']].reset_index(drop=True), bus_stop], axis=1)
    
    # Bus Shape
    bus_shape=gpd.GeoDataFrame(pd.concat([bus_route.loc[np.repeat(0, 3), ['UniRouteId','UniRouteName']].reset_index(drop=True), pd.DataFrame({'WKT':['wkt','wkt0','wkt1']})], axis=1),
                               geometry=gpd.GeoSeries.from_wkt([res['wkt'], res['wkt0'], res['wkt1']]), crs=4326)
    
    bus_stop_all=pd.concat([bus_stop_all, bus_stop]).reset_index(drop=True)
    bus_shape_all=pd.concat([bus_shape_all, bus_shape]).reset_index(drop=True)
    bus_route_all=pd.concat([bus_route_all, bus_route]).reset_index(drop=True)
    

