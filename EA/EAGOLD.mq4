#property strict
#property version   "0.915"
#property description "EAGOLD - observed BUY/SELL distance engine"

input int    MagicNumber       = 1001;
input double Lot               = 0.01;
input double Multiplier        = 1.20;
input int    DigitsLots        = 2;
input double LotIncrement      = 0.02;
input double MaxOpenLot        = 3.00;
input double TakeProfit        = 5.00;
input double SellProfit        = 30.00;
input double BasketLoss        = 100.00;
input int    SpreadLimit       = 100;
input int    WaitSeconds       = 0;
input double FirstStep         = 160;
input double MiniGrid1         = 250;
input double SmartGrid1        = 80;
input double MiniGrid2         = 80;
input double SmartGrid2        = 60;
input double PendingStepTrail  = 50;
input int    MaxTrades         = 2000;
input bool   EnableCloseBy     = false;
input double BuyProgressionTolerance = 10;

string EA_NAME = "EAGOLD";
datetime LastTradeTime = 0;
datetime LastBuyOpenTime = 0;
datetime LastBuyProgressionSource = 0;

double PointsToPrice(double points)
{
   return(points * Point);
}

double NormalizePrice(double price)
{
   return(NormalizeDouble(price, Digits));
}

bool SpreadOK()
{
   if(SpreadLimit <= 0) return(true);
   RefreshRates();
   return(((Ask-Bid)/Point) <= SpreadLimit);
}

bool WaitOK()
{
   if(WaitSeconds <= 0 || LastTradeTime <= 0) return(true);
   return((TimeCurrent()-LastTradeTime) >= WaitSeconds);
}

bool TradeCapacityOK()
{
   int count=0;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=MagicNumber) continue;
      count++;
   }
   return(count < MaxTrades);
}

bool IsEAGOLDOrder()
{
   return(OrderSymbol()==Symbol() && OrderMagicNumber()==MagicNumber);
}

bool HasPendingSide(int type)
{
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(!IsEAGOLDOrder()) continue;
      if(OrderType()==type) return(true);
   }
   return(false);
}

int CountOpenSide(int type)
{
   int count=0;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(!IsEAGOLDOrder()) continue;
      if(OrderType()==type) count++;
   }
   return(count);
}

bool GetLatestOpenInfo(int type,double &price,double &lots,datetime &openTime)
{
   price=0.0; lots=0.0; openTime=0;
   bool found=false;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(!IsEAGOLDOrder() || OrderType()!=type) continue;
      if(!found || OrderOpenTime()>openTime)
      {
         found=true;
         price=OrderOpenPrice();
         lots=OrderLots();
         openTime=OrderOpenTime();
      }
   }
   return(found);
}

double GetLastOpenPrice(int type)
{
   double price,lots; datetime t;
   if(GetLatestOpenInfo(type,price,lots,t)) return(price);
   return(0.0);
}

void SyncBuyExecutionState()
{
   double price,lots; datetime t;
   if(!GetLatestOpenInfo(OP_BUY,price,lots,t))
   {
      LastBuyOpenTime=0;
      return;
   }
   if(LastBuyOpenTime==0 || t>LastBuyOpenTime)
      LastBuyOpenTime=t;
}

// Observed lot model currently under validation.
double GetNextLot(int side)
{
   int n=CountOpenSide(side);
   double lots=Lot*MathPow(Multiplier,n)+(n*LotIncrement);
   lots=MathMax(LotIncrement,lots);
   lots=NormalizeDouble(lots,DigitsLots);
   if(lots>MaxOpenLot) lots=MaxOpenLot;
   return(lots);
}

int SendPending(int type,double lots,double price,string comment)
{
   if(!SpreadOK() || !TradeCapacityOK() || !WaitOK()) return(-1);
   RefreshRates();
   double stopLevel=MarketInfo(Symbol(),MODE_STOPLEVEL)*Point;
   if(type==OP_BUYSTOP && price<=Ask+stopLevel) return(-1);
   if(type==OP_SELLSTOP && price>=Bid-stopLevel) return(-1);
   price=NormalizePrice(price);
   int ticket=OrderSend(Symbol(),type,lots,price,0,0,0,comment,MagicNumber,0,clrNONE);
   if(ticket>0) LastTradeTime=TimeCurrent();
   else Print(EA_NAME," OrderSend failed type=",type," price=",DoubleToString(price,Digits)," error=",GetLastError());
   return(ticket);
}

bool ClosePosition(int ticket,double lots,int type,string reason)
{
   if(!OrderSelect(ticket,SELECT_BY_TICKET)) return(false);
   RefreshRates();
   double price=(type==OP_BUY ? Bid : Ask);
   bool ok=OrderClose(ticket,lots,NormalizePrice(price),0,clrNONE);
   if(ok)
   {
      LastTradeTime=TimeCurrent();
      Print(EA_NAME," ",reason," ticket=",ticket," lots=",DoubleToString(lots,DigitsLots)," close=",DoubleToString(price,Digits));
   }
   else Print(EA_NAME," OrderClose failed ticket=",ticket," error=",GetLastError());
   return(ok);
}

void DeletePendingSide(int type)
{
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(!IsEAGOLDOrder() || OrderType()!=type) continue;
      int ticket=OrderTicket();
      if(!OrderDelete(ticket)) Print(EA_NAME," OrderDelete failed ticket=",ticket," error=",GetLastError());
   }
}

void EnsureInitialPendings()
{
   if(CountOpenSide(OP_BUY)==0 && !HasPendingSide(OP_BUYSTOP))
   {
      RefreshRates();
      SendPending(OP_BUYSTOP,Lot,NormalizePrice(Ask+PointsToPrice(FirstStep)),"EAGOLD BUY INITIAL");
   }
   if(CountOpenSide(OP_SELL)==0 && !HasPendingSide(OP_SELLSTOP))
   {
      RefreshRates();
      SendPending(OP_SELLSTOP,Lot,NormalizePrice(Bid-PointsToPrice(FirstStep)),"EAGOLD SELL INITIAL");
   }
}

void TrailBuyStops()
{
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(!IsEAGOLDOrder() || OrderType()!=OP_BUYSTOP) continue;

      RefreshRates();
      double desired=NormalizePrice(Ask+PointsToPrice(FirstStep));
      double current=OrderOpenPrice();
      double trail=PointsToPrice(PendingStepTrail);
      double stopLevel=MarketInfo(Symbol(),MODE_STOPLEVEL)*Point;

      if(desired>=current) continue;
      if((current-desired)<trail) continue;
      if(desired<=Ask+stopLevel) continue;

      ResetLastError();
      if(!OrderModify(OrderTicket(),desired,0,0,0,clrNONE))
         Print(EA_NAME," BUYSTOP trail failed ticket=",OrderTicket()," error=",GetLastError());
      else
         Print(EA_NAME," BUYSTOP moved TOWARD price ticket=",OrderTicket()," from=",DoubleToString(current,Digits)," to=",DoubleToString(desired,Digits));
   }
}

void EnsureBuyResetStop()
{
   if(HasPendingSide(OP_BUYSTOP)) return;
   if(!SpreadOK() || !TradeCapacityOK() || !WaitOK()) return;
   RefreshRates();
   SendPending(OP_BUYSTOP,Lot,NormalizePrice(Ask+PointsToPrice(FirstStep)),"EAGOLD BUY RESET");
}

void ProcessBuyTakeProfit()
{
   if(TakeProfit<=0.0) return;
   bool closed=false;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(!IsEAGOLDOrder() || OrderType()!=OP_BUY) continue;
      RefreshRates();
      if(Bid<OrderOpenPrice()+TakeProfit) continue;
      if(ClosePosition(OrderTicket(),OrderLots(),OP_BUY,"BUY TP")) closed=true;
   }

   if(closed && CountOpenSide(OP_BUY)==0)
   {
      LastBuyProgressionSource=0;
      DeletePendingSide(OP_BUYSTOP);
      EnsureBuyResetStop();
   }
}

bool BuyProgressionTrigger(double lastBuy,double &target,string &mode)
{
   if(lastBuy<=0.0) return(false);
   if(CountOpenSide(OP_BUY)<=0 || CountOpenSide(OP_SELL)<=0) return(false);

   RefreshRates();
   target=NormalizePrice(Ask+PointsToPrice(FirstStep));

   double upper=lastBuy+PointsToPrice(MiniGrid1);
   double lower=lastBuy-PointsToPrice(MiniGrid1);
   double tol=PointsToPrice(BuyProgressionTolerance);

   if(target>=upper-tol)
   {
      mode="EXPANSION";
      return(true);
   }
   if(target<=lower+tol)
   {
      mode="RECOVERY";
      return(true);
   }
   return(false);
}

void EnsureNextBuyStop()
{
   SyncBuyExecutionState();
   if(HasPendingSide(OP_BUYSTOP)) return;
   if(CountOpenSide(OP_BUY)<=0 || CountOpenSide(OP_SELL)<=0) return;
   if(!SpreadOK() || !TradeCapacityOK() || !WaitOK()) return;

   double lastBuy,lastLots; datetime lastTime;
   if(!GetLatestOpenInfo(OP_BUY,lastBuy,lastLots,lastTime)) return;
   if(LastBuyProgressionSource==lastTime) return;

   double target=0.0;
   string mode="";
   if(!BuyProgressionTrigger(lastBuy,target,mode)) return;

   double lots=GetNextLot(OP_BUY);
   double stopLevel=MarketInfo(Symbol(),MODE_STOPLEVEL)*Point;
   if(target<=Ask+stopLevel) return;

   int ticket=SendPending(OP_BUYSTOP,lots,target,"EAGOLD BUY "+mode);
   if(ticket>0)
   {
      LastBuyProgressionSource=lastTime;
      Print(EA_NAME," BUY ",mode," source=",TimeToString(lastTime),
            " lastBuy=",DoubleToString(lastBuy,Digits),
            " target=",DoubleToString(target,Digits),
            " delta=",DoubleToString(target-lastBuy,Digits),
            " lots=",DoubleToString(lots,DigitsLots),
            " MiniGrid1=",DoubleToString(MiniGrid1,Digits));
   }
}

// Incremental SELL STOP rule:
// 1) Initial order is placed at Bid - FirstStep.
// 2) While no market position exists, the desired level follows Bid - FirstStep.
// 3) OrderModify is executed only when the desired level has advanced by at least PendingStepTrail.
double GetSellStartupTrailTarget()
{
   RefreshRates();
   return(NormalizePrice(Bid-PointsToPrice(FirstStep)));
}

void TrailSellStops()
{
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(!IsEAGOLDOrder() || OrderType()!=OP_SELLSTOP) continue;

      RefreshRates();

      double desired;
      if(CountOpenSide(OP_BUY)==0 && CountOpenSide(OP_SELL)==0)
         desired=GetSellStartupTrailTarget();
      else
      {
         double distance=PointsToPrice(SmartGrid1);
         desired=NormalizePrice(Bid-distance);
      }

      double current=OrderOpenPrice();
      double trail=PointsToPrice(PendingStepTrail);
      double stopLevel=MarketInfo(Symbol(),MODE_STOPLEVEL)*Point;

      if(desired<=current) continue;
      if((desired-current)<trail) continue;
      if(desired>=Bid-stopLevel) continue;

      ResetLastError();
      if(!OrderModify(OrderTicket(),desired,0,0,0,clrNONE))
         Print(EA_NAME," SELLSTOP trail failed ticket=",OrderTicket()," error=",GetLastError());
      else
         Print(EA_NAME," SELLSTOP moved TOWARD price ticket=",OrderTicket()," from=",DoubleToString(current,Digits)," to=",DoubleToString(desired,Digits)," trail=",DoubleToString(PendingStepTrail,0));
   }
}

void EnsureNextSellStop()
{
   if(HasPendingSide(OP_SELLSTOP)) return;
   if(CountOpenSide(OP_SELL)<=0) return;
   if(!SpreadOK() || !TradeCapacityOK() || !WaitOK()) return;

   double lastSell=GetLastOpenPrice(OP_SELL);
   if(lastSell<=0.0) return;
   RefreshRates();
   if(Bid-lastSell<PointsToPrice(2.0*FirstStep)) return;

   double lots=GetNextLot(OP_SELL);
   double target=NormalizePrice(Bid-PointsToPrice(FirstStep));
   double stopLevel=MarketInfo(Symbol(),MODE_STOPLEVEL)*Point;
   if(target>=Bid-stopLevel) return;

   SendPending(OP_SELLSTOP,lots,target,"EAGOLD SELL NEXT");
}

void ProcessSellProfit()
{
   if(SellProfit<=0.0) return;
   double total=0.0;
   bool hasSell=false;

   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(!IsEAGOLDOrder() || OrderType()!=OP_SELL) continue;
      hasSell=true;
      total += OrderProfit()+OrderSwap()+OrderCommission();
   }

   if(!hasSell || total<SellProfit) return;

   Print(EA_NAME," SELL BASKET TP total=",DoubleToString(total,2));
   DeletePendingSide(OP_SELLSTOP);

   for(int j=OrdersTotal()-1;j>=0;j--)
   {
      if(!OrderSelect(j,SELECT_BY_POS,MODE_TRADES)) continue;
      if(!IsEAGOLDOrder() || OrderType()!=OP_SELL) continue;
      ClosePosition(OrderTicket(),OrderLots(),OP_SELL,"SELL BASKET TP");
   }

   if(CountOpenSide(OP_SELL)==0 && !HasPendingSide(OP_SELLSTOP))
   {
      RefreshRates();
      SendPending(OP_SELLSTOP,Lot,NormalizePrice(Bid-PointsToPrice(FirstStep)),"EAGOLD SELL RESET");
   }
}

void ProcessCloseBy()
{
   if(!EnableCloseBy) return;
}

void UpdateDisplay()
{
   string text=EA_NAME+" v0.915";
   text += "\nBUY="+IntegerToString(CountOpenSide(OP_BUY));
   text += " SELL="+IntegerToString(CountOpenSide(OP_SELL));
   text += "\nMiniGrid1="+DoubleToString(MiniGrid1,Digits);
   text += " SmartGrid1="+DoubleToString(SmartGrid1,Digits);
   text += "\nMiniGrid2="+DoubleToString(MiniGrid2,Digits);
   text += " SmartGrid2="+DoubleToString(SmartGrid2,Digits);
   Comment(text);
}

int OnInit()
{
   SyncBuyExecutionState();
   Print(EA_NAME," v0.915 initialized. Test configuration: FirstStep=160 MiniGrid1=250 SmartGrid1=80 MiniGrid2=80 SmartGrid2=60 PendingStepTrail=50.");
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   Comment("");
}

void OnTick()
{
   ProcessSellProfit();
   ProcessBuyTakeProfit();
   TrailBuyStops();
   EnsureNextBuyStop();
   TrailSellStops();
   EnsureNextSellStop();
   EnsureInitialPendings();
   ProcessCloseBy();
   UpdateDisplay();
}