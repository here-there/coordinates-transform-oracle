--创建数据类型
create type LONLAT_RESULT_TYPE as OBJECT (
    LON number,
    LAT number
);

create or replace package TRANS_COORDS_UTIL is
  /**
     坐标转换工具集：WGS84、高德坐标、百度坐标互转
  */
  PI CONSTANT number := 3.14159265358979324;
  X_PI CONSTANT number := 3.14159265358979324 * 3000.0 / 180.0;

  function transformLon(x number, y number) return number; --转换经度
  function transformLat(x number, y number) return number; --转换纬度
  function delta(lon number, lat number) return LONLAT_RESULT_TYPE; --求转换增量
  function outOfChina(lon number, lat number) return boolean; --是否在中国范围内
  function gcj_encrypt(wgsLon number, wgsLat number) return LONLAT_RESULT_TYPE; -- WGS84 -> 国测局坐标 
  function gcj_decrypt(gcjLon number, gcjLat number) return LONLAT_RESULT_TYPE; -- 国测局坐标 -> WGS84
  function gcj_decrypt_exact(gcjLon number, gcjLat number) return LONLAT_RESULT_TYPE; -- 国测局坐标 -> WGS84(二分查找)
  function bd_encrypt(gcjLon number, gcjLat number) return LONLAT_RESULT_TYPE; -- 国测局坐标 -> 百度经纬度坐标（火星坐标）
  function bd_decrypt(bdLon number, bdLat number) return LONLAT_RESULT_TYPE; -- 百度经纬度坐标（火星坐标）-> 国测局坐标
  function mercator_encrypt(wgsLon number, wgsLat number) return LONLAT_RESULT_TYPE; -- WGS84 -> 墨卡托投影坐标
  function mercator_decrypt(mercatorLon number, mercatorLat number) return LONLAT_RESULT_TYPE; -- 墨卡托投影坐标 -> WGS84
  function distance(lonA number, latA number, lonB number, latB number) return number; -- 求两个点的距离（米）
end TRANS_COORDS_UTIL;



create or replace package BODY TRANS_COORDS_UTIL is
  

  FUNCTION transformLon(x number, y number) RETURN number IS
    V_LON number;
  BEGIN
    V_LON := 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * sqrt(abs(x));
    V_LON := V_LON + (20.0 * sin(6.0 * x * PI) + 20.0 * sin(2.0 * x * PI)) * 2.0 / 3.0;
    V_LON := V_LON + (20.0 * sin(x * PI) + 40.0 * sin(x / 3.0 * PI)) * 2.0 / 3.0;
    V_LON := V_LON + (150.0 * sin(x / 12.0 * PI) + 300.0 * sin(x / 30.0 * PI)) * 2.0 / 3.0;
    return V_LON;
  END;
  
  FUNCTION transformLat(x number, y number) RETURN number IS
    V_LAT number;
  BEGIN
    V_LAT := -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * sqrt(abs(x));
    V_LAT := V_LAT + (20.0 * sin(6.0 * x * PI) + 20.0 * sin(2.0 * x * PI)) * 2.0 / 3.0;
    V_LAT := V_LAT + (20.0 * sin(y * PI) + 40.0 * sin(y / 3.0 * PI)) * 2.0 / 3.0;
    V_LAT := V_LAT + (160.0 * sin(y / 12.0 * PI) + 320 * sin(y * PI / 30.0)) * 2.0 / 3.0;
    return V_LAT;
  END;
  
  function gcj_encrypt(wgsLon number, wgsLat number) return LONLAT_RESULT_TYPE is 
    result LONLAT_RESULT_TYPE;
    d LONLAT_RESULT_TYPE;
  begin
    if (TRANS_COORDS_UTIL.outOfChina(wgsLon, wgsLat) = true) then
      result := LONLAT_RESULT_TYPE(wgsLon, wgsLat);
    else
      d := TRANS_COORDS_UTIL.delta(wgsLon, wgsLat);
      result := LONLAT_RESULT_TYPE(wgsLon + d.LON, wgsLat + d.LAT);
    end if;
    return result;
  end;
  
  function gcj_decrypt(gcjLon number, gcjLat number) return LONLAT_RESULT_TYPE is
    result LONLAT_RESULT_TYPE;
    d LONLAT_RESULT_TYPE;
  begin
    if (TRANS_COORDS_UTIL.outOfChina(gcjLon, gcjLat) = true) then
      result := LONLAT_RESULT_TYPE(gcjLon, gcjLat);
    else
      d := TRANS_COORDS_UTIL.delta(gcjLon, gcjLat);
      result := LONLAT_RESULT_TYPE(gcjLon - d.LON, gcjLat - d.LAT);
    end if;
    return result;
  end;
  
  function gcj_decrypt_exact(gcjLon number, gcjLat number) return LONLAT_RESULT_TYPE is
    result LONLAT_RESULT_TYPE;
    d LONLAT_RESULT_TYPE;
  begin
    if (TRANS_COORDS_UTIL.outOfChina(gcjLon, gcjLat) = true) then
      result := LONLAT_RESULT_TYPE(gcjLon, gcjLat);
    else
      d := TRANS_COORDS_UTIL.delta(gcjLon, gcjLat);
      result := LONLAT_RESULT_TYPE(gcjLon - d.LON, gcjLat - d.LAT);
    end if;
    return result;
  end;
  
  function bd_encrypt(gcjLon number, gcjLat number) return LONLAT_RESULT_TYPE is
    x number;
    y number;
    z number;
    theta number;
    bdLon number;
    bdLat number;
  begin
    x := gcjLon;
    y := gcjLat;
    z := sqrt(x * x + y * y) + 0.00002 * sin(y * X_PI);
    theta := atan2(y, x) + 0.000003 * cos(x * X_PI);
    bdLon := z * cos(theta) + 0.0065;
    bdLat := z * sin(theta) + 0.006;
    return LONLAT_RESULT_TYPE(bdLon, bdLat);
  end;
  
  
  function bd_decrypt(bdLon number, bdLat number) return LONLAT_RESULT_TYPE is
    x number;
    y number;
    z number;
    theta number;
    gcjLon number;
    gcjLat number;
  begin
    x := bdLon - 0.0065;
    y := bdLat - 0.006;
    z := sqrt(x * x + y * y) - 0.00002 * sin(y * X_PI);
    theta := atan2(y, x) - 0.000003 * cos(x * X_PI);
    gcjLon := z * cos(theta);
    gcjLat := z * sin(theta);
    return LONLAT_RESULT_TYPE(gcjLon, gcjLat);
  end;

  function mercator_encrypt(wgsLon number, wgsLat number) return LONLAT_RESULT_TYPE is
    x number;
    y number;
  begin
    x := wgsLon * 20037508.34 / 180.0;
    y := ln(tan((90.0 + wgsLat) * PI / 360.0)) / (PI / 180.0);
    y := y * 20037508.34 / 180.0;
    return LONLAT_RESULT_TYPE(x, y);  
  end;
  
  function mercator_decrypt(mercatorLon number, mercatorLat number) return LONLAT_RESULT_TYPE is
    x number;
    y number;
  begin
    x := mercatorLon / 20037508.34 * 180.0;
    y := mercatorLat / 20037508.34 * 180.0;
    y := 180.0 / PI * (2 * atan(exp(y * PI / 180.)) - PI / 2);
    return LONLAT_RESULT_TYPE(x, y);  
  end;
  
  function distance(lonA number, latA number, lonB number, latB number) return number is
    earthR number := 6371000.0;
    x number;
    y number;
    s number;
    alpha number;
    distance number;
  begin
    x := cos(latA * PI / 180.0) * cos(latB * PI / 180.0) * cos((lonA - lonB) * PI / 180.0);
    y := sin(latA * PI / 180.0) * sin(latB * PI / 180.0);
    s := x + y;
    if s > 1 then
      s := 1;
    end if;
    if s < -1 then
      s := -1;
    end if;
    alpha := acos(s);
    distance := alpha * earthR;
    return distance;
  end;
  
  function delta(lon number, lat number) return LONLAT_RESULT_TYPE is 
    
    a number := 6378245.0; /*卫星椭球坐标投影到平面地图坐标系的投影因子。*/
    ee number := 0.00669342162296594323; /*椭球的偏心率*/
    
    lonlat LONLAT_RESULT_TYPE;
    dLat number;
    dLon number;
    radLat number;
    magic number;
    sqrtMagic number;
  begin
    dLat := transformLat(lon - 105.0, lat - 35.0);
    dLon := transformLon(lon - 105.0, lat - 35.0);
    radLat := lat / 180.0 * PI;
    magic := sin(radLat);
    magic := 1 - ee * magic * magic;
    sqrtMagic := sqrt(magic);
    dLat := (dLat * 180.0) / ((a * (1 - ee)) / (magic * sqrtMagic) * PI);
    dLon := (dLon * 180.0) / (a / sqrtMagic * cos(radLat) * PI);
    lonlat := LONLAT_RESULT_TYPE(dLon, dLat);
    return lonlat;
  end;
  
  function outOfChina(lon number, lat number) return boolean is
    result boolean := false;
  begin
    if (lon < 72.004) or (lon > 137.8347) then
      result := true;
    end if;
    if (lat < 0.8293) or (lat > 55.8271) then
      result := true;
    end if;
    return result;
  end;

end TRANS_COORDS_UTIL;
