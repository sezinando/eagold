//+------------------------------------------------------------------+
//|                                                   EAGOLD.mq4     |
//| EAGOLD - ZEUS observed pending/trailing engine                  |
//| Version 0.905 - observed two-engine / basket architecture       |
//+------------------------------------------------------------------+
#property strict
#property version   "000.905"
#property description "EAGOLD - observed BUY/SELL pending engines, stepped SELL trailing, observed lot ladder and isolated basket/close-by framework."

input int    MagicNumber              = 1001;
input double Lot                      = 0.01;
input double Multiplier               = 1.20;
input int    DigitsLots               = 2;
input double LotIncrement             = 0.01;
input double MaxOpenLot               = 3.00;
input double TakeProfit               = 5.00;
input double BasketProfit             = 4.00;
input double BasketLoss               = 100.00;
input int    SpreadLimit              = 100;
input int    WaitSeconds              = 0;
input int    FirstStep                = 160;
input int    MiniGrid1                = 240;
input int    SmartGrid1               = 150;
input int    PendingStepTrail         = 50;
input int    MaxTrades                = 2000;

// Observed-management switches. Basket/CloseBy remain OFF until their
// exact trigger is proven from additional tick/order samples.
input bool   EnableSellBasketClose    = false;
input bool   EnableCloseBy            = false;

color AvgBuyColor  = clrBlue;
color AvgSellColor = clrRed;
color PanelColor   = clrWhite;

string AvgBuyLineName   = "EAGOLD_AVG_BUY_LINE";
string AvgSellLineName  = "EAGOLD_AVG_SELL_LINE";
string AvgBuyTextName   = "EAGOLD_AVG_BUY_TEXT";
string AvgSellTextName  = "EAGOLD_AVG_SELL_TEXT";
string PanelName        = "EAGOLD_EXPOSURE_PANEL";

int      CycleNumber    = 0;
datetime LastTradeTime  = 0;

bool IsEAGOLDOrder()
{
   return(OrderSymbol()==Symbol() && OrderMagicNumber()==MagicNumber);
}

bool IsOpenPosition()
{
   return(OrderType()==OP_BUY || OrderType()==OP_SELL);
}

bool IsPendingOrder()
{
   int type=OrderType();
   return(type==OP_BUYSTOP || type==OP_SELLSTOP || type==OP_BUYLIMIT || type==OP_SELLLIMIT);
}

double PointsToPrice(int points)
{
   return(points*Point);
}

double NormalizePrice(double price)
{
   return(NormalizeDouble(price,Digits));
}

double NormalizeLot(double lots)
{
   double minLot=MarketInfo(Symbol(),MODE_MINLOT);
   double maxLot=MarketInfo(Symbol(),MODE_MAXLOT);
   double step=MarketInfo(Symbol(),MODE_LOTSTEP);
   if(step<=0.0) step=LotIncrement;
   if(step<=0.0) step=0.01;
   if(lots<minLot) lots=minLot;
   if(maxLot>0.0 && lots>maxLot) lots=maxLot;
   if(MaxOpenLot>0.0 && lots>MaxOpenLot) lots=MaxOpenLot;
   lots=MathRound(lots/step)*step;
   if(lots<minLot) lots=minLot;
   if(maxLot>0.0 && lots>maxLot) lots=maxLot;
   if(MaxOpenLot>0.0 && lots>MaxOpenLot) lots=MaxOpenLot;
   return(NormalizeDouble(lots,DigitsLots));
}

int CountOpenPositions()
{
   int count=0;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(IsEAGOLDOrder() && IsOpenPosition()) count++;
   }
   return(count);
}

int CountPendingOrders()
{
   int count=0;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(IsEAGOLDOrder() && IsPendingOrder()) count++;
   }
   return(count);
}

int CountSide(int side)
{
   int count=0;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(IsEAGOLDOrder() && OrderType()==side) count++;
   }
   return(count);
}

void GetSideExposure(int side,double &lots,double &pnl,int &count)
{
   lots=0.0;
   pnl=0.0;
   count=0;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(!IsEAGOLDOrder() || OrderType()!=side) continue;
      lots+=OrderLots();
      pnl+=OrderProfit()+OrderSwap()+OrderCommission();
      count++;
   }
}

bool GetSideAverage(int side,double &averagePrice)
{
   double weighted=0.0;
   double lots=0.0;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(!IsEAGOLDOrder() || OrderType()!=side) continue;
      weighted+=OrderOpenPrice()*OrderLots();
      lots+=OrderLots();
   }
   if(lots<=0.0)
   {
      averagePrice=0.0;
      return(false);
   }
   averagePrice=NormalizePrice(weighted/lots);
   return(true);
}

void DeleteObjectIfExists(string name)
{
   if(ObjectFind(0,name)>=0) ObjectDelete(0,name);
}

void DrawAverageLine(string lineName,string textName,double price,color lineColor,string label)
{
   if(ObjectFind(0,lineName)<0) ObjectCreate(0,lineName,OBJ_HLINE,0,0,price);
   ObjectSetDouble(0,lineName,OBJPROP_PRICE1,price);
   ObjectSetInteger(0,lineName,OBJPROP_COLOR,lineColor);
   ObjectSetInteger(0,lineName,OBJPROP_STYLE,STYLE_DASH);
   ObjectSetInteger(0,lineName,OBJPROP_WIDTH,1);
   ObjectSetInteger(0,lineName,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,lineName,OBJPROP_SELECTED,false);

   datetime t=(Bars>0 ? Time[0] : TimeCurrent());
   if(ObjectFind(0,textName)<0) ObjectCreate(0,textName,OBJ_TEXT,0,t,price);
   ObjectMove(0,textName,0,t,price);
   ObjectSetString(0,textName,OBJPROP_TEXT,label+" "+DoubleToString(price,Digits));
   ObjectSetString(0,textName,OBJPROP_FONT,"Arial");
   ObjectSetInteger(0,textName,OBJPROP_FONTSIZE,8);
   ObjectSetInteger(0,textName,OBJPROP_COLOR,lineColor);
   ObjectSetInteger(0,textName,OBJPROP_ANCHOR,ANCHOR_LEFT);
   ObjectSetInteger(0,textName,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,textName,OBJPROP_SELECTED,false);
}

void UpdateAveragePriceDisplay()
{
   double buyAvg,sellAvg;
   if(GetSideAverage(OP_BUY,buyAvg))
      DrawAverageLine(AvgBuyLineName,AvgBuyTextName,buyAvg,AvgBuyColor,"BUY AVG");
   else
   {
      DeleteObjectIfExists(AvgBuyLineName);
      DeleteObjectIfExists(AvgBuyTextName);
   }

   if(GetSideAverage(OP_SELL,sellAvg))
      DrawAverageLine(AvgSellLineName,AvgSellTextName,sellAvg,AvgSellColor,"SELL AVG");
   else
   {
      DeleteObjectIfExists(AvgSellLineName);
      DeleteObjectIfExists(AvgSellTextName);
   }
}

void CreateOrUpdatePanel()
{
   if(ObjectFind(0,PanelName)<0) ObjectCreate(0,PanelName,OBJ_LABEL,0,0,0);

   double buyLots,buyPnl,sellLots,sellPnl;
   int buyCount,sellCount;
   GetSideExposure(OP_BUY,buyLots,buyPnl,buyCount);
   GetSideExposure(OP_SELL,sellLots,sellPnl,sellCount);

   string text="EAGOLD v0.905 [OBSERVED ENGINE]\n"+
      "----------------------------------------------\n"+
      "OPEN BUY : "+IntegerToString(buyCount)+"  "+DoubleToString(buyLots,2)+" lot  P/L "+DoubleToString(buyPnl,2)+"\n"+
      "OPEN SELL: "+IntegerToString(sellCount)+"  "+DoubleToString(sellLots,2)+" lot  P/L "+DoubleToString(sellPnl,2)+"\n"+
      "PENDING  : "+IntegerToString(CountPendingOrders())+"\n"+
      "FirstStep="+IntegerToString(FirstStep)+
      "  MiniGrid1="+IntegerToString(MiniGrid1)+
      "  SmartGrid1="+IntegerToString(SmartGrid1)+"\n"+
      "TrailStep="+IntegerToString(PendingStepTrail)+
      "  SELL create trigger="+IntegerToString(FirstStep*2)+"\n"+
      "SELL basket="+(EnableSellBasketClose?"ON":"OFF")+
      "  CloseBy="+(EnableCloseBy?"ON":"OFF")+"\n"+
      "BUY close: individual TP\n"+
      "Balance: "+DoubleToString(AccountBalance(),2)+
      "  Equity: "+DoubleToString(AccountEquity(),2);

   ObjectSetString(0,PanelName,OBJPROP_TEXT,text);
   ObjectSetString(0,PanelName,OBJPROP_FONT,"Consolas");
   ObjectSetInteger(0,PanelName,OBJPROP_FONTSIZE,9);
   ObjectSetInteger(0,PanelName,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,PanelName,OBJPROP_XDISTANCE,10);
   ObjectSetInteger(0,PanelName,OBJPROP_YDISTANCE,20);
   ObjectSetInteger(0,PanelName,OBJPROP_COLOR,PanelColor);
   ObjectSetInteger(0,PanelName,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,PanelName,OBJPROP_SELECTED,false);
}

bool SpreadOK()
{
   if(SpreadLimit<=0) return(true);
   RefreshRates();
   return(((Ask-Bid)/Point)<=SpreadLimit);
}

bool WaitOK()
{
   if(WaitSeconds<=0 || LastTradeTime<=0) return(true);
   return((TimeCurrent()-LastTradeTime)>=WaitSeconds);
}

bool TradeCapacityOK()
{
   if(MaxTrades<=0) return(true);
   return((CountOpenPositions()+CountPendingOrders())<MaxTrades);
}

bool HasPendingSide(int type)
{
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(IsEAGOLDOrder() && OrderType()==type) return(true);
   }
   return(false);
}

bool SendPending(int type,double lots,double price,string comment)
{
   if(!SpreadOK() || !TradeCapacityOK()) return(false);
   RefreshRates();
   lots=NormalizeLot(lots);
   price=NormalizePrice(price);

   double stopLevel=MarketInfo(Symbol(),MODE_STOPLEVEL)*Point;
   if(type==OP_BUYSTOP && price<=Ask+stopLevel) return(false);
   if(type==OP_SELLSTOP && price>=Bid-stopLevel) return(false);

   ResetLastError();
   int ticket=OrderSend(Symbol(),type,lots,price,10,0,0,comment,MagicNumber,0,clrNONE);
   if(ticket<0)
   {
      Print("EAGOLD ERROR - pending send failed type=",type,
            " price=",DoubleToString(price,Digits)," err=",GetLastError());
      return(false);
   }

   LastTradeTime=TimeCurrent();
   Print("EAGOLD EVENT PENDING - ticket=",ticket,
         " type=",type," lots=",DoubleToString(lots,DigitsLots),
         " price=",DoubleToString(price,Digits));
   return(true);
}

bool ClosePosition(int ticket,double lots,int type,string reason)
{
   if(!OrderSelect(ticket,SELECT_BY_TICKET)) return(false);
   if(!IsEAGOLDOrder() || OrderType()!=type) return(false);
   RefreshRates();
   double price=(type==OP_BUY ? Bid : Ask);
   ResetLastError();
   if(!OrderClose(ticket,lots,price,10,clrNONE))
   {
      Print("EAGOLD ERROR - close failed ticket=",ticket," err=",GetLastError());
      return(false);
   }
   LastTradeTime=TimeCurrent();
   Print("EAGOLD EVENT CLOSE - ticket=",ticket,
         " side=",(type==OP_BUY?"BUY":"SELL"),
         " reason=",reason," price=",DoubleToString(price,Digits));
   return(true);
}

// Exact observed SELL ladder from the reverse-engineered history.
double ObservedLotByIndex(int index)
{
   if(index<=1) return(NormalizeLot(Lot));

   double ladder[12];
   ladder[0]=0.01;
   ladder[1]=0.03;
   ladder[2]=0.05;
   ladder[3]=0.08;
   ladder[4]=0.10;
   ladder[5]=0.12;
   ladder[6]=0.15;
   ladder[7]=0.18;
   ladder[8]=0.20;
   ladder[9]=0.23;
   ladder[10]=0.26;
   ladder[11]=0.30;

   if(index<=12) return(NormalizeLot(ladder[index-1]));

   double lots=ladder[11];
   for(int i=13;i<=index;i++)
      lots=NormalizeLot(lots*Multiplier);
   return(NormalizeLot(lots));
}

// Returns the most recently opened position on a side.
double LastOpenPrice(int side)
{
   datetime latest=0;
   double price=0.0;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(!IsEAGOLDOrder() || OrderType()!=side) continue;
      if(OrderOpenTime()>=latest)
      {
         latest=OrderOpenTime();
         price=OrderOpenPrice();
      }
   }
   return(price);
}

void EnsureInitialPendings()
{
   if(CountOpenPositions()>0 || CountPendingOrders()>0) return;
   if(!SpreadOK() || !TradeCapacityOK() || !WaitOK()) return;

   RefreshRates();
   double buyStop=NormalizePrice(Ask+PointsToPrice(FirstStep));
   double sellStop=NormalizePrice(Bid-PointsToPrice(FirstStep));

   CycleNumber++;
   SendPending(OP_BUYSTOP,Lot,buyStop,"EAGOLD INITIAL BUY STOP");
   SendPending(OP_SELLSTOP,Lot,sellStop,"EAGOLD INITIAL SELL STOP");
}

// Observed stepped SELL pending trail. The pending order is advanced only
// after price has moved approximately PendingStepTrail from the previous
// reference; this intentionally avoids a continuously moving pending order.
void TrailSellStops()
{
   if(PendingStepTrail<=0) return;
   RefreshRates();

   bool sideActive=(CountSide(OP_BUY)>0 || CountSide(OP_SELL)>0);
   int trailPoints=(sideActive && SmartGrid1>0 ? SmartGrid1 : PendingStepTrail);

   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(!IsEAGOLDOrder() || OrderType()!=OP_SELLSTOP) continue;

      double oldPrice=OrderOpenPrice();
      double desired=NormalizePrice(Bid-PointsToPrice(trailPoints));
      double step=PointsToPrice(PendingStepTrail);

      // The real history shows a stepped trail. Do not modify on every tick.
      if(desired<=oldPrice+Point/2.0) continue;
      if((desired-oldPrice)<step) continue;

      double stopLevel=MarketInfo(Symbol(),MODE_STOPLEVEL)*Point;
      if(desired>=Bid-stopLevel)
         desired=NormalizePrice(Bid-stopLevel);
      if(desired<=oldPrice+Point/2.0) continue;

      int ticket=OrderTicket();
      ResetLastError();
      if(OrderModify(ticket,desired,0,0,0,clrNONE))
      {
         Print("EAGOLD EVENT TRAIL SELL STOP - ticket=",ticket,
               " old=",DoubleToString(oldPrice,Digits),
               " new=",DoubleToString(desired,Digits),
               " distance=",trailPoints,
               " step=",PendingStepTrail);
      }
      else
         Print("EAGOLD ERROR - trail modify failed ticket=",ticket,
               " err=",GetLastError());
   }
}

// The observed history shows that the next SELL pending level is based on
// the last executed SELL plus FirstStep. Creation is gated by the observed
// approximately 2 x FirstStep advance before the pending is introduced.
void EnsureNextSellStop()
{
   if(HasPendingSide(OP_SELLSTOP)) return;

   double lastSell=LastOpenPrice(OP_SELL);
   if(lastSell<=0.0) return;
   if(!SpreadOK() || !TradeCapacityOK() || !WaitOK()) return;

   RefreshRates();
   double triggerDistance=PointsToPrice(FirstStep*2);
   if((Bid-lastSell)<triggerDistance) return;

   double target=NormalizePrice(lastSell+PointsToPrice(FirstStep));
   double stopLevel=MarketInfo(Symbol(),MODE_STOPLEVEL)*Point;
   if(target>=Bid-stopLevel) return;

   int index=CountSide(OP_SELL)+1;
   double lots=ObservedLotByIndex(index);
   SendPending(OP_SELLSTOP,lots,target,
               "EAGOLD NEXT SELL STOP #"+IntegerToString(index));
}

// BUY is an independent recycling engine. After a profitable BUY close,
// the next pending is placed from the current Ask using MiniGrid1.
void EnsureBuyStopAfterTP()
{
   if(HasPendingSide(OP_BUYSTOP)) return;
   if(!SpreadOK() || !TradeCapacityOK() || !WaitOK()) return;
   RefreshRates();

   double target=NormalizePrice(Ask+PointsToPrice(MiniGrid1));
   double stopLevel=MarketInfo(Symbol(),MODE_STOPLEVEL)*Point;
   if(target<=Ask+stopLevel) return;

   SendPending(OP_BUYSTOP,Lot,target,"EAGOLD BUY RECYCLE");
}

void ProcessBuyTakeProfit()
{
   if(TakeProfit<=0.0) return;

   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(!IsEAGOLDOrder() || OrderType()!=OP_BUY) continue;

      double target=OrderOpenPrice()+PointsToPrice((int)MathRound(TakeProfit/Point));
      if(Bid<target) continue;

      int ticket=OrderTicket();
      double lots=OrderLots();
      if(ClosePosition(ticket,lots,OP_BUY,"BUY TP"))
         EnsureBuyStopAfterTP();
   }
}

// Basket and CloseBy are intentionally isolated. The observed history proves
// both mechanisms exist, but the exact trigger cannot yet be derived from a
// single sample. Keeping them disabled by default prevents invented behavior.
void ProcessObservedManagement()
{
   if(EnableCloseBy)
   {
      // Reserved for the proven CloseBy trigger. No speculative execution.
   }

   if(EnableSellBasketClose)
   {
      // Reserved for the proven SELL basket trigger. No speculative execution.
   }
}

void OnInit()
{
   CreateOrUpdatePanel();
   UpdateAveragePriceDisplay();
   Print("EAGOLD v0.905 initialized - observed two-engine architecture");
}

void OnDeinit(const int reason)
{
   DeleteObjectIfExists(AvgBuyLineName);
   DeleteObjectIfExists(AvgSellLineName);
   DeleteObjectIfExists(AvgBuyTextName);
   DeleteObjectIfExists(AvgSellTextName);
   DeleteObjectIfExists(PanelName);
}

void OnTick()
{
   RefreshRates();

   EnsureInitialPendings();
   TrailSellStops();
   EnsureNextSellStop();
   ProcessBuyTakeProfit();
   ProcessObservedManagement();

   UpdateAveragePriceDisplay();
   CreateOrUpdatePanel();
}
//+------------------------------------------------------------------+
