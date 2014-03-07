--[[
Licensed to the Apache Software Foundation (ASF) under one
or more contributor license agreements.  See the NOTICE file
distributed with this work for additional information
regarding copyright ownership.  The ASF licenses this file
to you under the Apache License, Version 2.0 (the
"License"); you may not use this file except in compliance
with the License.  You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing,
software distributed under the License is distributed on an
"AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
KIND, either express or implied.  See the License for the
specific language governing permissions and limitations
under the License.
]]

--[[ mod_lua implementation of the server-status page ]]

-- pre-declare some variables defined at the bottom of this script:
local status_js, status_css

-- Handler function
function handle(r)

    -- Parse GET data, if any, and set content type
    local GET = r:parseargs()
    r.content_type = "text/html"

    -- Fetch server data
    local mpm = "prefork" -- assume prefork by default
    if r.mpm_query(14) == 1 then
        mpm = "event" -- this is event mpm
    elseif r.mpm_query(3) >= 1 then
        mpm = "worker" -- it's not event, but it's threaded, we'll assume worker mpm
    elseif r.mpm_query(2) == 1 then
		mpm = "winnt" -- it's threaded, but not worker nor event, so it's probably winnt
	end
    local maxServers = r.mpm_query(12);
    local maxThreads = r.mpm_query(6);
    local curServers = 0;
    local uptime = os.time() - r.started;
    local costs = {}
    local stime = 0;
    local utime = 0;
    local cons = 0;
    local bytes = 0;
    local threadActions = {}

    -- Fetch process/thread data
    for i=0,maxServers,1 do
        server = r.scoreboard_process(r, i);
        if server then
            if server.pid > 0 then
                curServers = curServers + 1
                for j = 0, maxThreads-1, 1 do
                    worker = r.scoreboard_worker(r, i, j)
                    if worker then
                        stime = stime + (worker.stimes or 0);
                        utime = utime + (worker.utimes or 0);
                        table.insert(costs, i .. "/" .. worker.tid .. ":" .. ((worker.utimes or 0) + (worker.stimes or 0)) .. ";" .. worker.access_count .. ";" .. worker.vhost:gsub(":%d+", "") .. ";" .. worker.request)
                        threadActions[worker.status] = (threadActions[worker.status] or 0) + 1
                        cons = cons + worker.access_count;
                        bytes = bytes + worker.bytes_served;
                    end
                end
            end
        end
    end

    -- Try to calculate the CPU max
    local maxCPU = 5000000
    while (maxCPU < (stime+utime)) do
        maxCPU = maxCPU * 2
    end


    -- If we only need the stats feed, compact it and hand it over
    if GET['view'] and GET['view'] == "worker_status" then
        local tbl = {threadActions[2] or 0, threadActions[4] or 0, threadActions[3] or 0 , threadActions[5] or 0 ,threadActions[8] or 0 ,threadActions[9] or 0}
        tbl[1] = tbl[1]
        tbl[2] = tbl[2]
        tbl[3] = tbl[3]
        tbl[4] = tbl[4]
        tbl[5] = tbl[5]
        r.content_type = "text/plain"
        r:puts(table.concat(tbl, ","), "\n", uptime, ",", cons, ",", bytes,"\n",
        curServers,",",maxServers, ",", maxThreads,"\n",
        stime,",",utime .. "\n" .. table.concat(costs, "\n"))
        return apache2.OK
    end



    -- Print out the HTML for the front page
    r:puts ( ([=[
<html>
  <head>
    <style>
    %s
    </style>
    <!--Load the AJAX API-->
    <script type="text/javascript" src="https://www.google.com/jsapi"></script>
    <script type="text/javascript">
        %s
    </script>
    <title>Server status for %s</title>
  </head>

  <body>
    <h2>Status for %s on %s</h2>
    <div style="width: 90%%; float: left; clear: both">
    <b>Server version:</b> %s<br/>
    <b>Server (re)started:</b> %s<br/>
    <b>Uptime: </b> <span id='uptime'></span><br/>
    <b>Server MPM:</b> %s<br/>
    <b>Generation:</b> %u<br/>
    <b>Current work-force:</b> <span id="current_threads">%u (%u processes x %u threads)</span><br/>
    <b>Maximum work-force:</b> <span id="max_threads">%u (%u processes x %u threads)</span><br/>
    <b>Connections accepted:</b> <span id="connections">%u (%.3f/sec)</span><br/>
    <b>Bytes transfered:</b> <span id="transfer"> %.2fMB (%.2fkB/sec, %.2fkB/req)</span><br/>
    </div>
    <!--Div that will hold the pie chart-->
    <div id="actions_div" style="float: left;"></div>
    <div id="traffic_div" style="float: left;"></div>
    <div style="clear: both"></div>
    <div id="status_div" style="float: left;"></div>
    <div id="cpu_div" style="float: left;"></div>
    <div id="costs_div" style="float: left; width:800px;"></div>

    <div style="clear: both;"><a id="show_link" href="javascript:void(0);" onclick="javascript:showDetails();">Show thread information</a></div>


]=]):format(
    status_css,
    status_js:format(   curServers, maxServers, maxThreads, threadActions[2] or 0, threadActions[4] or 0,
                        threadActions[3] or 0 , threadActions[5] or 0 ,threadActions[8] or 0 ,
                        threadActions[9] or 0 , maxCPU - utime - stime, stime, utime, cons, uptime, bytes
                    ),

    r.server_name, r.banner, r.server_name, r.banner, os.date("%c",r.started), mpm, r.mpm_query(15),
    curServers*maxThreads,curServers,maxThreads,maxServers*maxThreads, maxServers,maxThreads,cons,
    cons/uptime, bytes/1024/1024, bytes/uptime/1024, bytes/cons/1024
    ) );

    r:flush()

    -- Print out details about each process/thread
    for i=0,curServers-1,1 do
        local info = r.scoreboard_process(r, i);
        if info.pid ~= 0 then
            r:puts("<div id='srv_",i+1,"' style='display: none; clear: both;'><b>Server #", i+1, ":</b><br/>\n");
            for k, v in pairs(info) do
                r:puts(k, " = ", v, "<br/>\n");
            end
            r:puts([[<table id="server_]]..i..[[" name="server_]]..i..[[" border='1' style='font-family: arial, helvetica, sans-serif; font-size: 12px; border: 1px solid #666;'><tr>]])
            local worker = r.scoreboard_worker(r, i, 0);
            local p = 0;
            for k, v in pairs(worker) do
                if k ~= "pid" and k ~= "start_time" and k ~= "stop_time" then
                    r:puts("<th style='cursor:pointer;' onclick=\"sort(document.getElementById('server_",i,"'), ", p, ");\">",k,"</th>");
                end
                p = p + 1;
            end
            r:puts[[</tr>]]
            for j = 0, maxThreads-1 do
                worker = r.scoreboard_worker(r,i, j)
                if worker then

                    r:puts("<tr>");
                    for k, v in pairs(worker) do
                        if ( k == "last_used" and v > 3600) then v = os.date("%c", v/1000000) end
                        if k == "tid" then v = string.format("0x%x", v) end
                        if k == "status" then v = ({'D','.','R','W','K','L','D','C','G','I'})[tonumber(v)] or "??" end
                        if v == "" then v = "N/A" end
                        if k ~= "pid" and k ~= "start_time" and k ~= "stop_time" then r:puts("<td>",v,"</td>"); end
                    end
                    r:puts("</tr>");
                end
            end
            r:puts[[</table><hr/></div>]]
        end
    end

    -- HTML tail
    r:puts[[
  </body>
</html>
]]
    return apache2.OK;
end


------------------------------------
-- JavaScript and CSS definitions --
------------------------------------

-- Set up some JavaScripts:
status_js = [[
var worker_status;
    function refreshWorkerStatus() {
    }

    function fn(num) {
        num = num + "";
        num = num.replace(/(\d)(\d{9})$/, '$1,$2');
        num = num.replace(/(\d)(\d{6})$/, '$1,$2');
        num = num.replace(/(\d)(\d{3})$/, '$1,$2');
        return num;
    }

    function fnmb(num) {
        var add = "bytes";
        var dec = "";
        var mul = 1;
        if (num > 1024) { add = "KB"; mul= 1024; }
        if (num > (1024*1024)) { add = "MB"; mul= 1024*1024; }
        if (num > (1024*1024*1024)) { add = "GB"; mul= 1024*1024*1024; }
        if (num > (1024*1024*1024*1024)) { add = "TB"; mul= 1024*1024*1024*1024; }
        num = num / mul;
        if (add != "bytes") {
            dec = "." + Math.floor( (num - Math.floor(num)) * 100 );
        }
        return ( fn(Math.floor(num)) + dec + " " + add );
    }

    function sort(a,b){
        last_col = -1;
        var sort_reverse = false;
        var sortWay = a.getAttribute("sort_" + b);
        if (sortWay && sortWay == "forward") {
            a.setAttribute("sort_" + b, "reverse");
            sort_reverse = true;
        }
        else {
            a.setAttribute("sort_" + b, "forward");
        }
        var c,d,e,f,g,h,i;
        c=a.rows.length;
        if(c<1)return;
        d=a.rows[1].cells.length;
        e=1;
        var j=new Array(c);
        f=0;
        for(h=e;h<c;h++){
            var k=new Array(d);
            for(i=0;i<d;i++){
                cell_text="";
                cell_text=a.rows[h].cells[i].textContent;
                if(cell_text===undefined){cell_text=a.rows[h].cells[i].innerText;}
                k[i]=cell_text;
            }
            j[f++]=k;
        }
        var l=false;
        var m,n;
        if(b!=lastcol) lastseq="A";
        else{
            if(lastseq=="A") lastseq="D";
            lastseq="A";
        }

        g=c-1;

        for(h=0;h<g;h++){
            l=false;
            for(i=0;i<g-1;i++){
                m=j[i];
                n=j[i+1];
                if(lastseq=="A"){
                    var gt = (m[b]>n[b]) ? true : false;
                    var lt = (m[b]<n[b]) ? true : false;
                    if (n[b].match(/^(\d+)$/)) { gt = parseInt(m[b], 10) > parseInt(n[b], 10) ? true : false; lt = parseInt(m[b], 10) < parseInt(n[b], 10) ? true : false; }
                    if (sort_reverse) {gt = (!gt); lt = (!lt);}
                    if(gt){
                        j[i+1]=m;
                        j[i]=n;
                        l=true;
                    }
                }
                else{
                    if(lt){
                    j[i+1]=m;
                    j[i]=n;
                    l=true;
                }
            }
        }

        if(l==false)break}f=e;for(h=0;h<g;h++){m=j[h];for(i=0;i<d;i++){if(a.rows[f].cells[i].innerText!=undefined){a.rows[f].cells[i].innerText=m[i];}else{a.rows[f].cells[i].textContent=m[i]}}f++}lastcol=b;}
        var lastcol,lastseq;
        google.load("visualization", "1", {packages:["corechart"]});

    var currentServers =    %u;
    var maxServers =        %u;
    var threadsPerProcess = %u;


    var threadsIdle =       %u;
    var threadsWriting =    %u;
    var threadsReading =    %u;
    var threadsKeepalive =  %u;
    var threadsClosing =    %u;
    var threadsGraceful =   %u;

    var cpuIdle =           %u;
    var cpuSystem =         0;
    var cpuUser =           0;
    var cpuSystemTotal =    %u;
    var cpuUserTotal =      %u;
    var CPUmax =            100000;

    var connections =       %u;
    var uptime =            %u;
    var bytesTransfered =   %u;
    var bytesDifferenceIn = 0;
    var bytesDifferenceOut = 0;

    var pool_data;
    var pool_chart;
    var pool_options;

    var status_data;
    var status_chart;
    var status_options;

    var cpu_data;
    var cpu_chart;
    var cpu_options;

    var traffic_chart;
    var traffic_data;
    var traffic_options;

    var costs = [];
    var arr;

    function setup_charts() {
        // Thread pool chart
        pool_data = new google.visualization.DataTable();
        pool_chart =  new google.visualization.PieChart(document.getElementById('status_div'));
        pool_data.addColumn('string', 'Status');
        pool_data.addColumn('number', 'Workers');
        pool_data.addRows([
          ['Active', currentServers * threadsPerProcess],
          ['Reserved', (maxServers - currentServers) * threadsPerProcess]
        ]);
        pool_options = {'title':'Active vs reserved threads',
                       'width':350,
                       'height':300,
                        animation: {
                          duration: 1000,
                          easing: 'in'
                        }};

        // Thread status chart
        var d = new Date();
        var eta = (d.getHours() + "").replace(/^(\d)$/, "0$1") + ":" + (d.getMinutes() + "").replace(/^(\d)$/, "0$1") + ":" + (d.getSeconds() + "").replace(/^(\d)$/, "0$1");
        arr = [eta,threadsIdle,threadsWriting,threadsReading,threadsKeepalive,threadsClosing,threadsGraceful];
        status_data = google.visualization.arrayToDataTable([ ['Time', 'Idle', 'Writing', 'Reading', 'Keepalive', 'Closing', 'Graceful'], arr, arr ]);
        status_chart = new google.visualization.AreaChart(document.getElementById('actions_div'));
        status_options = {
              title: 'Worker actions',
              width: 600,
              height:300,
              isStacked: true,
                animation: {
                    duration: 1000,
                    easing: 'in'
                  }

            };

        // CPU time chart
        cpu_data = new google.visualization.DataTable();
        cpu_data.addColumn('string', 'Element');
        cpu_data.addColumn('number', 'Usage');
        cpu_data.addRows([
          ['Idle', cpuIdle],
          ['System', cpuSystem],
          ['User', cpuUser]
        ]);

        cpu_options = {'title':'CPU Usage',
                       'width':300,
                       'height':300,
                        animation: {
                          duration: 1000,
                          easing: 'in'
                        }
                      };
        cpu_chart = new google.visualization.BarChart(document.getElementById('cpu_div'));


        // traffic chart
        arr = [eta,0,0];
        traffic_data = google.visualization.arrayToDataTable([ ['Time', 'Input', 'Output'], arr, arr ]);
        traffic_chart = new google.visualization.AreaChart(document.getElementById('traffic_div'));
        traffic_options = {
              title: 'Traffic (bytes/sec)',
              width: 600,
              height:300,
              isStacked: true,
                animation: {
                    duration: 1000,
                    easing: 'in'
                  }

            };
        draw_charts();
    }

    // Init vars and XML HTTP Request object
    var visit_no = 0;
    var xmlhttp;
    if (window.XMLHttpRequest) { xmlhttp=new XMLHttpRequest(); }
    else { xmlhttp=new ActiveXObject("Microsoft.XMLHTTP"); }



    function updateCosts(arr) {
        var k;
        for (k in arr) {
            var xarr = arr[k].split(":",2);
            tid = xarr[0]; info = xarr[1];
            xarr = info.split(";");
            times = xarr[0]; lastVisit = xarr[1]; host = xarr[2]; url = xarr[3];
            if (costs[tid] && costs[tid].lastVisit != lastVisit) {
                costs[tid].show = true;
                costs[tid].otimes = costs[tid].times;
                costs[tid].times = parseInt(times,10) - (costs[tid].otimes ? costs[tid].otimes : 0);
                costs[tid].lastVisit = lastVisit;
            } else {
                costs[tid] = costs[tid] ? costs[tid] : [];
                costs[tid].otimes = parseInt(times,10);
                costs[tid].lastVisit = lastVisit;
            }
            costs[tid].url = (url.length > 0) ? url : (costs[tid].url ? costs[tid].url : "/");
            costs[tid].host = host;
        }
        var sortable = [];
        var x = 0;
        var tid;
        for (tid in costs) {
            sortable[x] = [tid, costs[tid].times ? costs[tid].times : 0];
            x++;
        }
        sortable.sort(function (a,b) { return (a[1] < b[1]); });
        var i = 0;
        var output = "<h4>Most expensive URLs:</h4><ol>";
        for (k=0; k < sortable.length; k++) {
            tid = sortable[k][0];
            if (costs[tid].show && costs[tid].url && costs[tid].url.length > 0) {
                i++;
                output = output + "<li><b>" + costs[tid].host + ": " + costs[tid].url + "</b> (" + costs[tid].times + " &micro;s)</li>";
                if (i == 10) { break; }
            }
        }
        output = output + "</ol>";
        document.getElementById("costs_div").innerHTML = output;
    }

    function update_charts() {
        visit_no++;
        if (xmlhttp && typeof(xmlhttp) != 'undefined') {
            xmlhttp.open("GET", location.href + "?view=worker_status", false);
            xmlhttp.send();
            var lines = xmlhttp.responseText.split("\n");
            workers = lines[0].split(",");
            var bytesBefore = bytesTransfered;
            var arr = lines[1].split(",");
            uptime = arr[0]; connections = arr[1]; bytesTransfered = arr[2];
            arr = lines[2].split(",");
            currentServers = arr[0]; maxServers = arr[1]; threadsPerProcess = arr[2];
            arr = lines[3].split(",");
            cpuSystemX = arr[0]; cpuUserX = arr[1];

            cpuSystem = Math.abs(parseInt(cpuSystemX,10) - cpuSystemTotal);
            cpuUser = Math.abs(parseInt(cpuUserX,10) - cpuUserTotal);
            cpuSystemTotal += cpuSystem;
            cpuUserTotal += cpuUser;
            bytesDifferenceOut = (parseInt(bytesTransfered,10) - bytesBefore) / 5;
            if (bytesDifferenceOut < 0) { bytesDifferenceOut = 0; } // In case we get a bad return value
            var d = new Date();
            var eta = (d.getHours() + "").replace(/^(\d)$/, "0$1") + ":" + (d.getMinutes() + "").replace(/^(\d)$/, "0$1") + ":" + (d.getSeconds() + "").replace(/^(\d)$/, "0$1");
            workers.unshift(eta);
            var k;
            for (k in workers) {
                if (k > 0) workers[k] = parseInt(workers[k],10);
            }
           status_data.addRow(workers);
           traffic_data.addRow([eta, 0, bytesDifferenceOut]);
           if (visit_no > 6 || visit_no == 1) { status_data.removeRow(0); traffic_data.removeRow(0); }
           lines.shift();
           lines.shift();
           lines.shift();
           lines.shift();
           updateCosts(lines);
        }
        draw_charts();
    }

    function draw_charts() {

        // Change connection/transfer info
        var obj = document.getElementById("connections");
        obj.innerHTML = fn(connections) + " (" + Math.floor(connections/uptime*1000)/1000 + "/sec)";
        var MB = fnmb(bytesTransfered);
        var KB = (bytesTransfered > 0) ? fnmb(bytesTransfered/connections) : 0;
        var KBs = fnmb(bytesTransfered/uptime);
        obj = document.getElementById("transfer");
        obj.innerHTML = MB + " (" + KB + "/req, " + KBs + "/sec)";

        // Active vs reserved threads
        var activeThreads = currentServers * threadsPerProcess;
        var maxThreads = maxServers * threadsPerProcess;
        var reservedThreads = (maxServers-currentServers) * threadsPerProcess;
        obj = document.getElementById("current_threads");
        obj.innerHTML = activeThreads + " (" + currentServers + " processes x " + threadsPerProcess + " threads)";
        obj = document.getElementById("max_threads");
        obj.innerHTML = maxThreads + " (" + maxServers + " processes x " + threadsPerProcess + " threads)";

        // CPU chart
        cpu_data.removeRow(0);
        cpu_data.removeRow(0);
        cpu_data.removeRow(0);
        cpuSystem = parseInt(cpuSystem,10);
        cpuUser = parseInt(cpuUser,10);

        while ( (cpuSystem+cpuUser) > CPUmax ) {
            CPUmax = CPUmax * 2;
        }
        cpu_data.addRow(["Idle", (CPUmax-cpuSystem-cpuUser)/(CPUmax/100)]);
        cpu_data.addRow(["System", cpuSystem/(CPUmax/100)]);
        cpu_data.addRow(["User", cpuUser/(CPUmax/100)]);

        // Active vs Reserved
        pool_data.removeRow(0);
        pool_data.removeRow(0);
        activeThreads = parseInt(activeThreads,10);
        reservedThreads = parseInt(reservedThreads,10);
        pool_data.addRow(["Active", activeThreads]);
        pool_data.addRow(["Reserved", reservedThreads]);

        // Draw charts
        pool_chart.draw(pool_data, pool_options);
        cpu_chart.draw(cpu_data, cpu_options);
        status_chart.draw(status_data, status_options);
        traffic_chart.draw(traffic_data, traffic_options);

        // Uptime calculation
        var uptime_div = document.getElementById('uptime');
        var u_d = Math.floor(uptime/86400);
        var u_h = Math.floor((uptime%%86400)/3600);
        var u_m = Math.floor((uptime%%3600)/60);
        var u_s = Math.floor(uptime %%60);
        var str =  u_d + " day" + (u_d != 1 ? "s, " : ", ") + u_h + " hour" + (u_h != 1 ? "s, " : ", ") + u_m + " minute" + (u_m != 1 ? "s, " : ", ") + u_s + " second" + (u_s != 1 ? "s" : "");
        uptime_div.innerHTML = str;

        setTimeout(update_charts, 5000);
    }

    google.setOnLoadCallback(setup_charts);

    var showing = false;
    function showDetails() {
        for (i=1; i < 1000; i++) {
            var obj = document.getElementById("srv_" + i);
            if (obj) {
                if (showing) { obj.style.display = "none"; }
                else { obj.style.display = "block"; }
            }
        }
        var link = document.getElementById("show_link");
        showing = (!showing);
        if (showing) { link.innerHTML = "Hide thread information"; }
        else { link.innerHTML = "Show thread information"; }
    }
]]


-- Set up some styles:
status_css = [[
    html {
    font-size: 14px;
    margin: 20px;
    }

    body {
        background-color: #fff;
        color: #036;
        padding: 0 1em 0 0;
        margin: 0;
        font-family: Arial, Helvetica, sans-serif;
        font-weight: normal;
    }

    pre, code {
        font-family: "Courier New", Courier, monospace;
    }

    strong {
        font-weight: bold;
    }

    q, em, var {
        font-style: italic;
    }
    /* h1                     */
    /* ====================== */
    h1 {
        padding: 0.2em;
        margin: 0;
        border: 1px solid #405871;
        background-color: inherit;
        color: #036;
        text-decoration: none;
        font-size: 22px;
        font-weight: bold;
    }

    /* h2                     */
    /* ====================== */
    h2 {
        padding: 0.2em 0 0.2em 0.7em;
        margin: 0 0 0.5em 0;
        text-decoration: none;
        font-size: 18px;
        font-weight: bold;
        background-color: #405871;
        color: #fff;
    }
]]