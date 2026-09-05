//+------------------------------------------------------------------+
//|                                                   EAGOLD.mq4     |
//| EAGOLD - ZEUS observed pending/trailing engine                  |
//| Version 0.906 - SELL profit basket closure                     |
//+------------------------------------------------------------------+
#property strict
#property version   "000.906"
#property description "EAGOLD - observed BUY/SELL engines, stepped SELL trailing, observed lot ladder and SELL profit basket closure."

input int    MagicNumber       = 1001;
input double Lot               = 0.01;
input double Multiplier        = 1.20;
input int    DigitsLots        = 2;
input double LotIncrement      = 0.01;
input double MaxOpenLot        = 3.00;
input double TakeProfit        = 5.00;
input double SellProfit        = 30.00;
input double BasketLoss        = 100.00;
input int    SpreadLimit       = 100;
input int    WaitSeconds       = 0;
input int    FirstStep         = 160;
input int    MiniGrid1         = 240;
input int    SmartGrid1        = 150;
input int    PendingStepTrail  = 50;
input int    MaxTrades         = 2000;

// CloseBy remains disabled until its exact observed trigger is proven.
input bool   EnableCloseBy     = false;

color AvgBuyColor  = clrBlue;
color AvgSellColor = clrRed;
color PanelColor   = clrWhite;

string AvgBuyLineName  = "EAGOLD_AVG_BUY_LINE";
string AvgSellLineName = "EAGOLD_AVG_SELL_LINE";
string AvgBuyTextName  = "EAGOLD_AVG_BUY_TEXT";
string AvgSellTextName = "EAGOLD_AVG_SELL_TEXT";
string PanelName       = "EAGOLD_EXPOSURE_PANEL";

datetime LastTradeTime = 0;

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
         " price=",DoubleToString(price,Digits)," comment=",comment);
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

void DeletePendingSide(int type,string reason)
{
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(!IsEAGOLDOrder() || OrderType()!=type) continue;
      int ticket=OrderTicket();
      ResetLastError();
      if(OrderDelete(ticket,clrNONE))
         Print("EAGOLD EVENT DELETE PENDING - ticket=",ticket," reason=",reason);
      else
         Print("EAGOLD ERROR - pending delete failed ticket=",ticket," err=",GetLastError());
   }
}

// Exact observed SELL ladder from reverse-engineered history.
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
   SendPending(OP_BUYSTOP,Lot,buyStop,"EAGOLD INITIAL BUY STOP");
   SendPending(OP_SELLSTOP,Lot,sellStop,"EAGOLD INITIAL SELL STOP");
}

// Stepped SELL pending trailing.
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

      if(desired<=oldPrice+Point/2.0) continue;
      if((desired-oldPrice)<step) continue;

      double stopLevel=MarketInfo(Symbol(),MODE_STOPLEVEL)*Point;
      if(desired>=Bid-stopLevel) desired=NormalizePrice(Bid-stopLevel);
      if(desired<=oldPrice+Point/2.0) continue;

      int ticket=OrderTicket();
      ResetLastError();
      if(OrderModify(ticket,desired,0,0,0,clrNONE))
      {
         Print("EAGOLD EVENT TRAIL SELL STOP - ticket=",ticket,
               " old=",DoubleToString(oldPrice,Digits),
               " new=",DoubleToString(desired,Digits),
               " distance=",trailPoints," step=",PendingStepTrail);
      }
      else
         Print("EAGOLD ERROR - trail modify failed ticket=",ticket," err=",GetLastError());
   }
}

// After a SELL is executed, create the next SELL pending only after the
// observed approximately 2 x FirstStep advance. The pending level itself is
// last SELL + FirstStep.
void EnsureNextSellStop()
{
   if(HasPendingSide(OP_SELLSTOP)) return;

   double lastSell=LastOpenPrice(OP_SELL);
   if(lastSell<=0.0) return;
   if(!SpreadOK() || !TradeCapacityOK() || !WaitOK()) return;

   RefreshRates();
   if((Bid-lastSell)<PointsToPrice(FirstStep*2)) return;

   double target=NormalizePrice(lastSell+PointsToPrice(FirstStep));
   double stopLevel=MarketInfo(Symbol(),MODE_STOPLEVEL)*Point;
   if(target>=Bid-stopLevel) return;

   int index=CountSide(OP_SELL)+1;
   double lots=ObservedLotByIndex(index);
   SendPending(OP_SELLSTOP,lots,target,"EAGOLD NEXT SELL STOP #"+IntegerToString(index));
}

// After a profitable BUY close, recycle an independent BUY STOP.
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

      double target=OrderOpenPrice()+TakeProfit;
      if(Bid<target) continue;

      int ticket=OrderTicket();
      double lots=OrderLots();
      if(ClosePosition(ticket,lots,OP_BUY,"BUY TP"))
         EnsureBuyStopAfterTP();
   }
}

// SELL PROFIT is a side-specific basket target. It sums the current SELL
// positions including swap/commission. When the target is reached, all SELL
// positions are closed together, pending SELL orders are removed, and a new
// 0.01 SELL STOP is started from Bid - FirstStep. BUY positions are untouched.
void ProcessSellProfit()
{
   if(SellProfit<=0.0) return;

   double sellLots,sellPnl;
   int sellCount;
   GetSideExposure(OP_SELL,sellLots,sellPnl,sellCount);
   if(sellCount<=0) return;
   if(sellPnl<SellProfit) return;

   Print("EAGOLD EVENT SELL PROFIT TARGET - pnl=",DoubleToString(sellPnl,2),
         " target=",DoubleToString(SellProfit,2),
         " positions=",sellCount," lots=",DoubleToString(sellLots,DigitsLots));

   DeletePendingSide(OP_SELLSTOP,"SELL PROFIT RESET");

   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(!IsEAGOLDOrder() || OrderType()!=OP_SELL) continue;
      int ticket=OrderTicket();
      double lots=OrderLots();
      ClosePosition(ticket,lots,OP_SELL,"SELL PROFIT");
   }

   // Start a fresh SELL cycle independently of the BUY engine.
   if(!HasPendingSide(OP_SELLSTOP) && SpreadOK() && TradeCapacityOK())
   {
      RefreshRates();
      double target=NormalizePrice(Bid-PointsToPrice(FirstStep));
      SendPending(OP_SELLSTOP,Lot,target,"EAGOLD SELL PROFIT RESET");
   }
}

void ProcessCloseBy()
{
   if(!EnableCloseBy) return;
   // Reserved. The historical sample proves OrderCloseBy exists, but its
   // trigger is not yet sufficiently determined for automatic execution.
}

void OnInit()
{
   Print("EAGOLD v0.906 initialized - SELL PROFIT=",DoubleToString(SellProfit,2));
}

void OnDeinit(const int reason)
{
   if(ObjectFind(0,AvgBuyLineName)>=0) ObjectDelete(0,AvgBuyLineName);
   if(ObjectFind(0,AvgSellLineName)>=0) ObjectDelete(0,AvgSellLineName);
   if(ObjectFind(0,AvgBuyTextName)>=0) ObjectDelete(0,AvgBuyTextName);
   if(ObjectFind(0,AvgSellTextName)>=0) ObjectDelete(0,AvgSellTextName);
   if(ObjectFind(0,PanelName)>=0) ObjectDelete(0,PanelName);
}

void UpdateDisplay()
{
   double buyLots,buyPnl,sellLots,sellPnl;
   int buyCount,sellCount;
   GetSideExposure(OP_BUY,buyLots,buyPnl,buyCount);
   GetSideExposure(OP_SELL,sellLots,sellPnl,sellCount);

   string text="EAGOLD v0.906 [OBSERVED ENGINE]\n"+
      "BUY  : "+IntegerToString(buyCount)+" / "+DoubleToString(buyLots,2)+" lot / P/L "+DoubleToString(buyPnl,2)+"\n"+
      "SELL : "+IntegerToString(sellCount)+" / "+DoubleToString(sellLots,2)+" lot / P/L "+DoubleToString(sellPnl,2)+"\n"+
      "PENDING: "+IntegerToString(CountPendingOrders())+"\n"+
      "FirstStep="+IntegerToString(FirstStep)+"  TrailStep="+IntegerToString(PendingStepTrail)+"\n"+
      "SELL Profit="+DoubleToString(SellProfit,2)+"  CloseBy="+(EnableCloseBy?"ON":"OFF")+"\n"+
      "Balance="+DoubleToString(AccountBalance(),2)+" Equity="+DoubleToString(AccountEquity(),2);

   if(ObjectFind(0,PanelName)<0) ObjectCreate(0,PanelName,OBJ_LABEL,0,0,0);
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

void OnTick()
{
   RefreshRates();

   // SELL PROFIT is evaluated before new SELL exposure is added, so the
   // basket can close as soon as its monetary target is reached.
   ProcessSellProfit();
   ProcessBuyTakeProfit();
   TrailSellStops();
   EnsureNextSellStop();
   EnsureInitialPendings();
   ProcessCloseBy();
   UpdateDisplay();
}
//+------------------------------------------------------------------+
