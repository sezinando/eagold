#property strict
#property version   "0.909"
#property description "EAGOLD - observed BUY/SELL distance engine"

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
input double FirstStep         = 160;
input double MiniGrid1         = 240;
input double SmartGrid1        = 150;
input double PendingStepTrail  = 50;
input int    MaxTrades         = 2000;
input bool   EnableCloseBy     = false;

string EA_NAME = "EAGOLD";
datetime LastTradeTime = 0;

// BUY progression was re-measured on the longer 01/07 H1 sample.
// Pending BUY levels repeatedly differ from the latest BUY by about 2.42
// price units. 242 points is used as the reference, with a 10-point tolerance.
input double BuyProgression          = 242;
input double BuyProgressionTolerance = 10;

double BuyLevelLot = 0.01;
datetime LastBuyOpenTime = 0;
datetime LastBuyProgressionSource = 0;

// -----------------------------------------------------------------------------
// Utility
// -----------------------------------------------------------------------------
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
      BuyLevelLot=MathMax(Lot,LotIncrement);
      LastBuyOpenTime=0;
      return;
   }

   if(LastBuyOpenTime==0)
   {
      LastBuyOpenTime=t;
      BuyLevelLot=lots;
      return;
   }

   if(t>LastBuyOpenTime)
   {
      LastBuyOpenTime=t;
      BuyLevelLot=lots;
      Print(EA_NAME," BUY LEVEL updated lot=",DoubleToString(BuyLevelLot,DigitsLots));
   }
}

int FindBuyLadderIndex(double lots)
{
   double ladder[12];
   ladder[0]=0.01; ladder[1]=0.03; ladder[2]=0.05; ladder[3]=0.08;
   ladder[4]=0.10; ladder[5]=0.12; ladder[6]=0.15; ladder[7]=0.18;
   ladder[8]=0.20; ladder[9]=0.23; ladder[10]=0.26; ladder[11]=0.30;
   for(int i=0;i<12;i++)
      if(MathAbs(lots-ladder[i]) <= (LotIncrement*0.51)) return(i);
   return(-1);
}

double GetNextBuyLot()
{
   double ladder[12];
   ladder[0]=0.01; ladder[1]=0.03; ladder[2]=0.05; ladder[3]=0.08;
   ladder[4]=0.10; ladder[5]=0.12; ladder[6]=0.15; ladder[7]=0.18;
   ladder[8]=0.20; ladder[9]=0.23; ladder[10]=0.26; ladder[11]=0.30;

   double current=BuyLevelLot;
   if(current<=0.0) current=MathMax(Lot,LotIncrement);

   int idx=FindBuyLadderIndex(current);
   double next;
   if(idx>=0 && idx<11) next=ladder[idx+1];
   else if(idx==11) next=ladder[11]*Multiplier;
   else next=current*Multiplier;

   next=MathMax(LotIncrement,next);
   next=NormalizeDouble(next,DigitsLots);
   if(next>MaxOpenLot) next=MaxOpenLot;
   return(next);
}

double GetNextSellLot(int sellCount)
{
   double ladder[12];
   ladder[0]=0.01; ladder[1]=0.03; ladder[2]=0.05; ladder[3]=0.08;
   ladder[4]=0.10; ladder[5]=0.12; ladder[6]=0.15; ladder[7]=0.18;
   ladder[8]=0.20; ladder[9]=0.23; ladder[10]=0.26; ladder[11]=0.30;
   double lots;
   if(sellCount<12) lots=ladder[sellCount];
   else lots=ladder[11]*MathPow(Multiplier,sellCount-11);
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

// -----------------------------------------------------------------------------
// Initial engine
// -----------------------------------------------------------------------------
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

// -----------------------------------------------------------------------------
// BUY ENGINE v0.909
// -----------------------------------------------------------------------------
void TrailBuyStops()
{
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(!IsEAGOLDOrder() || OrderType()!=OP_BUYSTOP) continue;
      RefreshRates();
      double desired=NormalizePrice(Ask+PointsToPrice(FirstStep));
      double current=OrderOpenPrice();
      if(MathAbs(desired-current)<PointsToPrice(PendingStepTrail)) continue;
      double stopLevel=MarketInfo(Symbol(),MODE_STOPLEVEL)*Point;
      if(desired<=Ask+stopLevel) continue;
      if(!OrderModify(OrderTicket(),desired,0,0,0,clrNONE))
         Print(EA_NAME," BUYSTOP trail failed ticket=",OrderTicket()," error=",GetLastError());
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
   if(closed)
   {
      if(CountOpenSide(OP_BUY)==0)
      {
         BuyLevelLot=MathMax(Lot,LotIncrement);
         LastBuyProgressionSource=0;
         DeletePendingSide(OP_BUYSTOP);
         EnsureBuyResetStop();
      }
   }
}

bool BuyProgressionTrigger(double lastBuy,double &target,string &mode)
{
   if(lastBuy<=0.0) return(false);
   if(CountOpenSide(OP_BUY)<=0 || CountOpenSide(OP_SELL)<=0) return(false);
   RefreshRates();
   target=NormalizePrice(Ask+PointsToPrice(FirstStep));
   double upper=lastBuy+PointsToPrice(BuyProgression);
   double lower=lastBuy-PointsToPrice(BuyProgression);
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

   // One progression order per executed BUY state. This prevents a canceled
   // pending order from being recreated repeatedly at the same level.
   if(LastBuyProgressionSource==lastTime) return;

   double target=0.0;
   string mode="";
   if(!BuyProgressionTrigger(lastBuy,target,mode)) return;

   double lots=GetNextBuyLot();
   if(lots<=0.0) return;
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
            " lots=",DoubleToString(lots,DigitsLots));
   }
}

// -----------------------------------------------------------------------------
// SELL engine - preserved from validated v0.906 behavior
// -----------------------------------------------------------------------------
void TrailSellStops()
{
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(!IsEAGOLDOrder() || OrderType()!=OP_SELLSTOP) continue;
      RefreshRates();
      double distance=(CountOpenSide(OP_BUY)>0 || CountOpenSide(OP_SELL)>0)
                      ? PointsToPrice(SmartGrid1) : PointsToPrice(PendingStepTrail);
      double desired=NormalizePrice(Bid+distance);
      double current=OrderOpenPrice();
      if(desired<=current) continue;
      if((desired-current)<PointsToPrice(PendingStepTrail)) continue;
      double stopLevel=MarketInfo(Symbol(),MODE_STOPLEVEL)*Point;
      if(desired>=Bid-stopLevel) continue;
      if(!OrderModify(OrderTicket(),OrderOpenPrice(),0,0,0,clrNONE))
         Print(EA_NAME," SELLSTOP trail failed ticket=",OrderTicket()," error=",GetLastError());
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
   int sellCount=CountOpenSide(OP_SELL);
   double lots=GetNextSellLot(sellCount);
   double target=NormalizePrice(lastSell+PointsToPrice(FirstStep));
   double stopLevel=MarketInfo(Symbol(),MODE_STOPLEVEL)*Point;
   if(target<=Bid+stopLevel) return;
   SendPending(OP_SELLSTOP,lots,target,"EAGOLD SELL NEXT");
}

void ProcessSellProfit()
{
   if(SellProfit<=0.0) return;
   double total=0.0; bool hasSell=false;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(!IsEAGOLDOrder() || OrderType()!=OP_SELL) continue;
      hasSell=true;
      total+=OrderProfit()+OrderSwap()+OrderCommission();
   }
   if(!hasSell || total<SellProfit) return;
   Print(EA_NAME," SELL BASKET TARGET reached total=",DoubleToString(total,2));
   DeletePendingSide(OP_SELLSTOP);
   for(int pass=0;pass<3;pass++)
   {
      bool closedAny=false;
      for(int i=OrdersTotal()-1;i>=0;i--)
      {
         if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
         if(!IsEAGOLDOrder() || OrderType()!=OP_SELL) continue;
         if(ClosePosition(OrderTicket(),OrderLots(),OP_SELL,"SELL BASKET")) closedAny=true;
      }
      if(!closedAny) break;
   }
   if(CountOpenSide(OP_SELL)==0)
   {
      RefreshRates();
      SendPending(OP_SELLSTOP,Lot,NormalizePrice(Bid-PointsToPrice(FirstStep)),"EAGOLD SELL RESET");
   }
}

void ProcessCloseBy()
{
   if(!EnableCloseBy) return;
   // Reserved. The H1 sample proves partial CloseBy/residual reconstruction,
   // but the exact trigger and matching priority are intentionally not yet
   // automated here.
}

void UpdateDisplay()
{
   Comment(EA_NAME," v0.909\n",
           "BUY open: ",CountOpenSide(OP_BUY)," | SELL open: ",CountOpenSide(OP_SELL),"\n",
           "BUY level lot: ",DoubleToString(BuyLevelLot,DigitsLots),"\n",
           "TP: ",DoubleToString(TakeProfit,2)," | SELL basket: ",DoubleToString(SellProfit,2),"\n",
           "FirstStep: ",DoubleToString(FirstStep,0)," | BUY progression: ",DoubleToString(BuyProgression,0));
}

int OnInit()
{
   SyncBuyExecutionState();
   Print(EA_NAME," v0.909 initialized");
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
