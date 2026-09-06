#property strict
#property indicator_chart_window
#property version   "1.000"
#property description "EAGOLD - Basket / Profit / Exposure Monitor"

input int    MagicNumber       = 1001;
input double TakeProfit        = 5.00;
input int    PanelCorner       = 0;
input int    PanelX            = 10;
input int    PanelY            = 20;
input int    FontSize          = 10;
input string PanelFont         = "Consolas";
input bool   PersistExtremes   = true;

string PREFIX = "EAGOLD_MON_";
double g_minTotalProfit = 0.0;
double g_maxTotalLots   = 0.0;
bool   g_initializedExtremes = false;

string GVMinProfit(){ return(PREFIX+Symbol()+"_"+IntegerToString(MagicNumber)+"_MINPROFIT"); }
string GVMaxLots(){ return(PREFIX+Symbol()+"_"+IntegerToString(MagicNumber)+"_MAXLOTS"); }

bool IsEAGOLDOrder()
{
   return(OrderSymbol()==Symbol() && OrderMagicNumber()==MagicNumber);
}

void LoadExtremes()
{
   g_minTotalProfit=0.0;
   g_maxTotalLots=0.0;
   if(PersistExtremes)
   {
      if(GlobalVariableCheck(GVMinProfit())) g_minTotalProfit=GlobalVariableGet(GVMinProfit());
      if(GlobalVariableCheck(GVMaxLots()))   g_maxTotalLots=GlobalVariableGet(GVMaxLots());
   }
   g_initializedExtremes=true;
}

void SaveExtremes()
{
   if(!PersistExtremes) return;
   GlobalVariableSet(GVMinProfit(),g_minTotalProfit);
   GlobalVariableSet(GVMaxLots(),g_maxTotalLots);
}

void ResetExtremes()
{
   g_minTotalProfit=0.0;
   g_maxTotalLots=0.0;
   if(PersistExtremes)
   {
      GlobalVariableSet(GVMinProfit(),0.0);
      GlobalVariableSet(GVMaxLots(),0.0);
   }
}

void ReadState(int &buyCount,double &buyLots,double &buyProfit,int &buyPending,
               int &sellCount,double &sellLots,double &sellProfit,int &sellPending,
               double &totalProfit,double &totalLots,double &netLots,int &totalPending)
{
   buyCount=0; buyLots=0.0; buyProfit=0.0; buyPending=0;
   sellCount=0; sellLots=0.0; sellProfit=0.0; sellPending=0;
   totalProfit=0.0; totalLots=0.0; netLots=0.0; totalPending=0;

   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(!IsEAGOLDOrder()) continue;

      int type=OrderType();
      if(type==OP_BUY)
      {
         buyCount++;
         buyLots+=OrderLots();
         buyProfit+=OrderProfit()+OrderSwap()+OrderCommission();
      }
      else if(type==OP_SELL)
      {
         sellCount++;
         sellLots+=OrderLots();
         sellProfit+=OrderProfit()+OrderSwap()+OrderCommission();
      }
      else if(type==OP_BUYSTOP)
      {
         buyPending++;
         totalPending++;
      }
      else if(type==OP_SELLSTOP)
      {
         sellPending++;
         totalPending++;
      }
   }

   totalProfit=buyProfit+sellProfit;
   totalLots=buyLots+sellLots;
   netLots=buyLots-sellLots;

   if(!g_initializedExtremes) LoadExtremes();

   if(totalProfit<g_minTotalProfit)
   {
      g_minTotalProfit=totalProfit;
      SaveExtremes();
   }
   if(totalLots>g_maxTotalLots)
   {
      g_maxTotalLots=totalLots;
      SaveExtremes();
   }
}

void CreateLabel(string name,int row)
{
   if(ObjectFind(0,name)>=0) return;
   ObjectCreate(0,name,OBJ_LABEL,0,0,0);
   ObjectSetInteger(0,name,OBJPROP_CORNER,PanelCorner);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,PanelX);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,PanelY+row*(FontSize+5));
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,FontSize);
   ObjectSetString(0,name,OBJPROP_FONT,PanelFont);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clrWhite);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
}

void SetLabel(string name,string text,int row)
{
   CreateLabel(name,row);
   ObjectSetString(0,name,OBJPROP_TEXT,text);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,PanelX);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,PanelY+row*(FontSize+5));
}

void DeletePanel()
{
   for(int i=ObjectsTotal(0)-1;i>=0;i--)
   {
      string name=ObjectName(0,i);
      if(StringFind(name,PREFIX,0)==0) ObjectDelete(0,name);
   }
}

string Money(double value)
{
   return(DoubleToString(value,2));
}

string Lots(double value)
{
   return(DoubleToString(value,2));
}

void UpdatePanel()
{
   int buyCount,sellCount,buyPending,sellPending,totalPending;
   double buyLots,sellLots,buyProfit,sellProfit,totalProfit,totalLots,netLots;
   ReadState(buyCount,buyLots,buyProfit,buyPending,
             sellCount,sellLots,sellProfit,sellPending,
             totalProfit,totalLots,netLots,totalPending);

   int row=0;
   SetLabel(PREFIX+"TITLE","EAGOLD MONITOR   XAUUSD",row++);
   SetLabel(PREFIX+"SEP1","----------------------------------------",row++);
   SetLabel(PREFIX+"BUY",StringFormat("BUY   %3d pos  %6s lot  P/L %10s",buyCount,Lots(buyLots),Money(buyProfit)),row++);
   SetLabel(PREFIX+"SELL",StringFormat("SELL  %3d pos  %6s lot  P/L %10s",sellCount,Lots(sellLots),Money(sellProfit)),row++);
   SetLabel(PREFIX+"BTP",StringFormat("BUY target:  %10s",Money(buyCount*TakeProfit)),row++);
   SetLabel(PREFIX+"STP",StringFormat("SELL target: %10s",Money(sellCount*TakeProfit)),row++);
   SetLabel(PREFIX+"SEP2","----------------------------------------",row++);
   SetLabel(PREFIX+"TOTAL",StringFormat("TOTAL P/L       %12s",Money(totalProfit)),row++);
   SetLabel(PREFIX+"MIN",StringFormat("MENOR P/L       %12s",Money(g_minTotalProfit)),row++);
   SetLabel(PREFIX+"LOTS",StringFormat("LOTES ATUAIS    %12s",Lots(totalLots)),row++);
   SetLabel(PREFIX+"MAXLOTS",StringFormat("MAIOR ACUM. LOT %10s",Lots(g_maxTotalLots)),row++);
   SetLabel(PREFIX+"NET",StringFormat("EXPOS. LIQUIDA  %12s",Lots(netLots)),row++);
   SetLabel(PREFIX+"PEND",StringFormat("PENDENTES       %12d",totalPending),row++);
   SetLabel(PREFIX+"PBUY",StringFormat("  BUY STOP      %12d",buyPending),row++);
   SetLabel(PREFIX+"PSELL",StringFormat("  SELL STOP     %12d",sellPending),row++);
   SetLabel(PREFIX+"SEP3","----------------------------------------",row++);
   SetLabel(PREFIX+"INFO","Min P/L e Max Lotes persistem por Symbol/Magic",row++);
   SetLabel(PREFIX+"TIME",StringFormat("Atualizado: %s",TimeToString(TimeCurrent(),TIME_SECONDS)),row++);
   ChartRedraw(0);
}

int OnInit()
{
   LoadExtremes();
   UpdatePanel();
   EventSetTimer(1);
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   DeletePanel();
}

void OnTimer()
{
   UpdatePanel();
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
   return(rates_total);
}
