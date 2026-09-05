//+------------------------------------------------------------------+
//|                                      EAGOLD_TICK_LOGGER.mq4       |
//| EAGOLD - Tick-by-tick market recorder for ZEUS reverse engineering|
//+------------------------------------------------------------------+
#property strict
#property indicator_chart_window
#property version   "001.000"
#property description "Records every indicator tick with sequence, server time, Bid, Ask and spread for later order-history correlation."

input string LogFileName       = "EAGOLD_TICKS_XAUUSD.csv";
input bool   ClearFileOnInit   = true;
input bool   FlushEveryTick    = true;
input bool   ShowStatusOnChart = true;

int      g_fileHandle   = INVALID_HANDLE;
ulong    g_tickIndex    = 0;
uint     g_startTickMs  = 0;
datetime g_startServer  = 0;
bool     g_ready        = false;

string ShortFileName()
{
   return(LogFileName);
}

string TickDateTime(datetime t)
{
   return(TimeToString(t,TIME_DATE|TIME_SECONDS));
}

bool OpenLogFile()
{
   if(ClearFileOnInit)
      FileDelete(LogFileName,FILE_COMMON);

   g_fileHandle=FileOpen(LogFileName,
                         FILE_CSV|FILE_READ|FILE_WRITE|FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_COMMON,
                         ';');

   if(g_fileHandle==INVALID_HANDLE)
   {
      Print("EAGOLD TICK LOGGER ERROR - FileOpen failed file=",LogFileName,
            " err=",GetLastError());
      return(false);
   }

   FileSeek(g_fileHandle,0,SEEK_END);

   if(FileTell(g_fileHandle)==0)
   {
      FileWrite(g_fileHandle,
                "TickIndex",
                "ServerTime",
                "ServerTimeMscApprox",
                "ElapsedMsc",
                "Bid",
                "Ask",
                "SpreadPoints",
                "SpreadPrice",
                "Last",
                "Volume",
                "Flags",
                "Symbol",
                "Digits",
                "Point");
      FileFlush(g_fileHandle);
   }

   return(true);
}

void CloseLogFile()
{
   if(g_fileHandle!=INVALID_HANDLE)
   {
      FileFlush(g_fileHandle);
      FileClose(g_fileHandle);
      g_fileHandle=INVALID_HANDLE;
   }
}

void WriteStatus()
{
   if(!ShowStatusOnChart) return;

   string status;
   if(!g_ready)
   {
      status="EAGOLD TICK LOGGER\nERROR: file not open";
   }
   else
   {
      status="EAGOLD TICK LOGGER v1.000\n"+
             "File: "+ShortFileName()+"\n"+
             "Ticks: "+IntegerToString((int)g_tickIndex)+"\n"+
             "Common\\Files\n"+
             "Server: "+TickDateTime(TimeCurrent());
   }

   Comment(status);
}

bool WriteTick()
{
   if(g_fileHandle==INVALID_HANDLE) return(false);

   MqlTick tick;
   if(!SymbolInfoTick(Symbol(),tick))
   {
      Print("EAGOLD TICK LOGGER ERROR - SymbolInfoTick failed err=",GetLastError());
      return(false);
   }

   uint nowMs=GetTickCount();
   uint elapsed=nowMs-g_startTickMs;

   // MT4 exposes the market tick time with second resolution in MqlTick.
   // GetTickCount supplies a local monotonic millisecond sequence reference.
   // The exact tick ordering is therefore preserved by TickIndex even when
   // the broker/tester timestamp itself has no millisecond component.
   long serverMscApprox=(long)g_startServer*1000L+(long)elapsed;

   double spreadPoints=0.0;
   if(Point>0.0)
      spreadPoints=(tick.ask-tick.bid)/Point;

   g_tickIndex++;

   FileWrite(g_fileHandle,
             (string)g_tickIndex,
             TickDateTime(tick.time),
             LongToString(serverMscApprox),
             (string)elapsed,
             DoubleToString(tick.bid,Digits),
             DoubleToString(tick.ask,Digits),
             DoubleToString(spreadPoints,1),
             DoubleToString(tick.ask-tick.bid,Digits),
             DoubleToString(tick.last,Digits),
             LongToString((long)tick.volume),
             LongToString((long)tick.flags),
             Symbol(),
             IntegerToString(Digits),
             DoubleToString(Point,Digits));

   if(FlushEveryTick)
      FileFlush(g_fileHandle);

   return(true);
}

int OnInit()
{
   IndicatorShortName("EAGOLD Tick Logger v1.000");

   g_tickIndex=0;
   g_startTickMs=GetTickCount();
   g_startServer=TimeCurrent();

   g_ready=OpenLogFile();
   WriteStatus();

   if(!g_ready)
      return(INIT_FAILED);

   Print("EAGOLD TICK LOGGER START - symbol=",Symbol(),
         " file=",LogFileName,
         " common=",TerminalInfoString(TERMINAL_COMMONDATA_PATH));

   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   CloseLogFile();
   Comment("");
   Print("EAGOLD TICK LOGGER STOP - symbol=",Symbol(),
         " ticks=",IntegerToString((int)g_tickIndex),
         " reason=",IntegerToString(reason));
}

int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   if(!g_ready) return(rates_total);

   WriteTick();
   WriteStatus();

   return(rates_total);
}
//+------------------------------------------------------------------+
