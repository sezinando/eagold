#property strict
#property version   "0.908"
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

// BUY observed progression module.
// The logs show the next BUY level is approximately 2.5 price units
// above/below the last executed BUY, depending on the current state.
// FirstStep remains the placement distance from Ask to BUY STOP.
double BuyProgression = 2.50;
double BuyProgressionTolerance = 0.15;

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
   double spread = (Ask - Bid) / Point;
   return(spread <= SpreadLimit);
}

bool WaitOK()
{
   if(WaitSeconds <= 0 || LastTradeTime <= 0) return(true);
   return((TimeCurrent() - LastTradeTime) >= WaitSeconds);
}

bool TradeCapacityOK()
{
   int count = 0;
   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
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
   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsEAGOLDOrder()) continue;
      if(OrderType()==type) return(true);
   }
   return(false);
}

int CountOpenSide(int type)
{
   int count=0;
   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsEAGOLDOrder()) continue;
      if(OrderType()==type) count++;
   }
   return(count);
}

double GetLastOpenPrice(int type)
{
   datetime latest=0;
   double price=0.0;
   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsEAGOLDOrder() || OrderType()!=type) continue;
      if(OrderOpenTime()>=latest)
      {
         latest=OrderOpenTime();
         price=OrderOpenPrice();
      }
   }
   return(price);
}

double GetHighestOpenBuyLot()
{
   double highest=0.0;
   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsEAGOLDOrder() || OrderType()!=OP_BUY) continue;
      if(OrderLots()>highest) highest=OrderLots();
   }
   return(highest);
}

int FindBuyLadderIndex(double lots)
{
   double ladder[12];
   ladder[0]=0.01; ladder[1]=0.03; ladder[2]=0.05; ladder[3]=0.08;
   ladder[4]=0.10; ladder[5]=0.12; ladder[6]=0.15; ladder[7]=0.18;
   ladder[8]=0.20; ladder[9]=0.23; ladder[10]=0.26; ladder[11]=0.30;

   for(int i=0; i<12; i++)
      if(MathAbs(lots-ladder[i]) < (LotIncrement*0.51)) return(i);

   return(-1);
}

double GetNextBuyLot()
{
   // Observed BUY ladder: 0.01, 0.03, 0.05, 0.08, 0.10, 0.12,
   // then 0.15, 0.18, 0.20, 0.23, 0.26, 0.30, followed by multiplier.
   double ladder[12];
   ladder[0]=0.01; ladder[1]=0.03; ladder[2]=0.05; ladder[3]=0.08;
   ladder[4]=0.10; ladder[5]=0.12; ladder[6]=0.15; ladder[7]=0.18;
   ladder[8]=0.20; ladder[9]=0.23; ladder[10]=0.26; ladder[11]=0.30;

   double highest=GetHighestOpenBuyLot();
   if(highest<=0.0)
      return(MathMin(MaxOpenLot,NormalizeDouble(MathMax(Lot,LotIncrement),DigitsLots)));

   int idx=FindBuyLadderIndex(highest);
   double next;

   if(idx>=0 && idx<11)
      next=ladder[idx+1];
   else if(idx==11)
      next=ladder[11]*Multiplier;
   else
      next=highest*Multiplier;

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
   if(sellCount < 12) lots=ladder[sellCount];
   else lots=ladder[11] * MathPow(Multiplier, sellCount-11);

   lots=MathMax(LotIncrement, lots);
   lots=NormalizeDouble(lots, DigitsLots);
   if(lots > MaxOpenLot) lots=MaxOpenLot;
   return(lots);
}

int SendPending(int type, double lots, double price, string comment)
{
   if(!SpreadOK() || !TradeCapacityOK() || !WaitOK()) return(-1);
   RefreshRates();

   double stopLevel=MarketInfo(Symbol(),MODE_STOPLEVEL)*Point;
   if(type==OP_BUYSTOP && price <= Ask+stopLevel) return(-1);
   if(type==OP_SELLSTOP && price >= Bid-stopLevel) return(-1);

   price=NormalizePrice(price);
   int ticket=OrderSend(Symbol(),type,lots,price,0,0,0,comment,MagicNumber,0,clrNONE);
   if(ticket>0) LastTradeTime=TimeCurrent();
   return(ticket);
}

bool ClosePosition(int ticket, double lots, int type, string reason)
{
   if(!OrderSelect(ticket, SELECT_BY_TICKET)) return(false);
   RefreshRates();
   double price=(type==OP_BUY ? Bid : Ask);
   bool ok=OrderClose(ticket,lots,NormalizePrice(price),0,clrNONE);
   if(ok)
   {
      LastTradeTime=TimeCurrent();
      Print(EA_NAME," ",reason," ticket=",ticket," lots=",DoubleToString(lots,DigitsLots),
            " close=",DoubleToString(price,Digits));
   }
   else
      Print(EA_NAME," OrderClose failed ticket=",ticket," error=",GetLastError());
   return(ok);
}

void DeletePendingSide(int type)
{
   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsEAGOLDOrder() || OrderType()!=type) continue;
      int ticket=OrderTicket();
      if(!OrderDelete(ticket))
         Print(EA_NAME," OrderDelete failed ticket=",ticket," error=",GetLastError());
   }
}

// -----------------------------------------------------------------------------
// Initial engine
// -----------------------------------------------------------------------------
void EnsureInitialPendings()
{
   if(CountOpenSide(OP_BUY)==0 && !HasPendingSide(OP_BUYSTOP))
   {
      if(SpreadOK() && TradeCapacityOK() && WaitOK())
      {
         RefreshRates();
         double target=NormalizePrice(Ask+PointsToPrice(FirstStep));
         SendPending(OP_BUYSTOP,Lot,target,"EAGOLD BUY INITIAL");
      }
   }

   if(CountOpenSide(OP_SELL)==0 && !HasPendingSide(OP_SELLSTOP))
   {
      if(SpreadOK() && TradeCapacityOK() && WaitOK())
      {
         RefreshRates();
         double target=NormalizePrice(Bid-PointsToPrice(FirstStep));
         SendPending(OP_SELLSTOP,Lot,target,"EAGOLD SELL INITIAL");
      }
   }
}

// -----------------------------------------------------------------------------
// BUY ENGINE v0.908
// Observed behavior now implemented:
// 1) BUY STOP placement = Ask + FirstStep.
// 2) BUY STOP trails downward/upward by following Ask + FirstStep,
//    with the same PendingStepTrail modification threshold used by SELL.
// 3) BUY positions close individually at Bid >= OpenPrice + TakeProfit.
// 4) After a BUY reset/TP, the next base BUY STOP is 0.01 at Ask+FirstStep.
// 5) When BUY and SELL structures coexist, the BUY engine can advance its
//    ladder in either direction. Observed next-level spacing is about 2.5
//    price units from the last executed BUY.
// 6) Recovery: pending target is approximately 2.5 below last BUY.
// 7) Expansion: pending target is approximately 2.5 above last BUY.
// 8) Next BUY lot follows the observed ladder 0.01 -> 0.03 -> 0.05 -> 0.08...
// 9) Pending BUY is state-dependent and may be canceled when the BUY structure
//    resets; this is handled by the reset path after BUY TP.
// -----------------------------------------------------------------------------
void TrailBuyStops()
{
   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsEAGOLDOrder() || OrderType()!=OP_BUYSTOP) continue;

      RefreshRates();
      double desired=NormalizePrice(Ask+PointsToPrice(FirstStep));
      double current=OrderOpenPrice();

      // BUY STOP follows Ask in both directions, but only advances when the
      // observed 50-point modification threshold has been reached.
      if(MathAbs(desired-current) < PointsToPrice(PendingStepTrail)) continue;

      double stopLevel=MarketInfo(Symbol(),MODE_STOPLEVEL)*Point;
      if(desired <= Ask+stopLevel) continue;

      int ticket=OrderTicket();
      if(!OrderModify(ticket,desired,0,0,0,clrNONE))
         Print(EA_NAME," BUYSTOP trail failed ticket=",ticket," error=",GetLastError());
   }
}

void EnsureBuyResetStop()
{
   if(HasPendingSide(OP_BUYSTOP)) return;
   if(!SpreadOK() || !TradeCapacityOK() || !WaitOK()) return;

   RefreshRates();
   double target=NormalizePrice(Ask+PointsToPrice(FirstStep));
   double stopLevel=MarketInfo(Symbol(),MODE_STOPLEVEL)*Point;
   if(target<=Ask+stopLevel) return;

   SendPending(OP_BUYSTOP,Lot,target,"EAGOLD BUY RESET");
}

void ProcessBuyTakeProfit()
{
   if(TakeProfit<=0.0) return;

   bool resetRequired=false;

   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsEAGOLDOrder() || OrderType()!=OP_BUY) continue;

      double target=OrderOpenPrice()+TakeProfit;
      RefreshRates();
      if(Bid < target) continue;

      int ticket=OrderTicket();
      double lots=OrderLots();
      if(ClosePosition(ticket,lots,OP_BUY,"BUY TP"))
         resetRequired=true;
   }

   if(resetRequired)
   {
      // A profitable BUY closes the current BUY cycle. Any higher-level
      // pending BUY belongs to the old state and is invalidated before the
      // fresh 0.01 reset is armed.
      DeletePendingSide(OP_BUYSTOP);
      if(CountOpenSide(OP_BUY)==0)
         EnsureBuyResetStop();
   }
}

bool BuyExpansionOrRecoveryTrigger(double lastBuy, double &target, string &mode)
{
   if(lastBuy<=0.0) return(false);
   if(CountOpenSide(OP_BUY)<=0 || CountOpenSide(OP_SELL)<=0) return(false);

   RefreshRates();

   // The observed pending target itself is approximately +/-2.5 from the
   // last BUY. Since target = Ask + FirstStep, the market trigger naturally
   // occurs about FirstStep earlier than the target level.
   double upper=lastBuy + BuyProgression;
   double lower=lastBuy - BuyProgression;
   double tolerance=BuyProgressionTolerance;
   double candidate=NormalizePrice(Ask+PointsToPrice(FirstStep));

   if(candidate >= upper-tolerance)
   {
      target=candidate;
      mode="EXPANSION";
      return(true);
   }

   if(candidate <= lower+tolerance)
   {
      target=candidate;
      mode="RECOVERY";
      return(true);
   }

   return(false);
}

void EnsureNextBuyStop()
{
   if(HasPendingSide(OP_BUYSTOP)) return;
   if(CountOpenSide(OP_BUY)<=0 || CountOpenSide(OP_SELL)<=0) return;
   if(!SpreadOK() || !TradeCapacityOK() || !WaitOK()) return;

   double lastBuy=GetLastOpenPrice(OP_BUY);
   if(lastBuy<=0.0) return;

   double target=0.0;
   string mode="";
   if(!BuyExpansionOrRecoveryTrigger(lastBuy,target,mode)) return;

   double lots=GetNextBuyLot();
   if(lots<=0.0) return;

   double stopLevel=MarketInfo(Symbol(),MODE_STOPLEVEL)*Point;
   if(target<=Ask+stopLevel) return;

   int ticket=SendPending(OP_BUYSTOP,lots,target,"EAGOLD BUY "+mode);
   if(ticket>0)
   {
      Print(EA_NAME," BUY ",mode,
            " lastBuy=",DoubleToString(lastBuy,Digits),
            " target=",DoubleToString(target,Digits),
            " delta=",DoubleToString(target-lastBuy,Digits),
            " lots=",DoubleToString(lots,DigitsLots));
   }
}

// -----------------------------------------------------------------------------
// SELL engine
// -----------------------------------------------------------------------------
void TrailSellStops()
{
   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsEAGOLDOrder() || OrderType()!=OP_SELLSTOP) continue;

      RefreshRates();
      double distance;
      if(CountOpenSide(OP_BUY)>0 || CountOpenSide(OP_SELL)>0)
         distance=PointsToPrice(SmartGrid1);
      else
         distance=PointsToPrice(PendingStepTrail);

      double desired=NormalizePrice(Bid+distance);
      double current=OrderOpenPrice();

      if(desired <= current) continue;
      if((desired-current) < PointsToPrice(PendingStepTrail)) continue;

      double stopLevel=MarketInfo(Symbol(),MODE_STOPLEVEL)*Point;
      if(desired >= Bid-stopLevel) continue;

      int ticket=OrderTicket();
      if(!OrderModify(ticket,OrderOpenPrice(),0,0,0,clrNONE))
         Print(EA_NAME," SELLSTOP trail failed ticket=",ticket," error=",GetLastError());
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
   double triggerDistance=PointsToPrice(2.0*FirstStep);
   if(Bid-lastSell < triggerDistance) return;

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

   double total=0.0;
   bool hasSell=false;
   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsEAGOLDOrder() || OrderType()!=OP_SELL) continue;
      hasSell=true;
      total += OrderProfit()+OrderSwap()+OrderCommission();
   }

   if(!hasSell || total < SellProfit) return;

   Print(EA_NAME," SELL BASKET TARGET reached total=",DoubleToString(total,2),
         " target=",DoubleToString(SellProfit,2));

   DeletePendingSide(OP_SELLSTOP);

   for(int pass=0; pass<3; pass++)
   {
      bool closedAny=false;
      for(int i=OrdersTotal()-1; i>=0; i--)
      {
         if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
         if(!IsEAGOLDOrder() || OrderType()!=OP_SELL) continue;
         int ticket=OrderTicket();
         double lots=OrderLots();
         if(ClosePosition(ticket,lots,OP_SELL,"SELL BASKET")) closedAny=true;
      }
      if(!closedAny) break;
   }

   if(CountOpenSide(OP_SELL)==0)
   {
      RefreshRates();
      double target=NormalizePrice(Bid-PointsToPrice(FirstStep));
      SendPending(OP_SELLSTOP,Lot,target,"EAGOLD SELL RESET");
   }
}

void ProcessCloseBy()
{
   if(!EnableCloseBy) return;
   // Reserved: exact CloseBy trigger is not yet sufficiently proven.
}

void UpdateDisplay()
{
   Comment(EA_NAME," v0.908\n",
           "BUY open: ",CountOpenSide(OP_BUY),
           " | SELL open: ",CountOpenSide(OP_SELL),"\n",
           "BUY TP: ",DoubleToString(TakeProfit,2),
           " | SELL basket: ",DoubleToString(SellProfit,2),"\n",
           "FirstStep: ",DoubleToString(FirstStep,0),
           " | BuyProgression: ",DoubleToString(BuyProgression,2),
           " | SmartGrid1: ",DoubleToString(SmartGrid1,0));
}

// -----------------------------------------------------------------------------
// MT4 events
// -----------------------------------------------------------------------------
int OnInit()
{
   Print(EA_NAME," v0.908 initialized");
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
