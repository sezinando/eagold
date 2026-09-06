#property strict
#property version   "0.064"
#property description "EAGOLD - BUY/SELL independent machines - Rules 1 to 8"

input int    MagicNumber              = 1001;
input double Lot                      = 0.01;
input double Multiplier               = 1.10;
input int    DigitsLots               = 2;
input double LotIncrement             = 0.02;
input double MaxOpenLot               = 3.00;
input double TakeProfit               = 5.00;
input double SellProfit               = 30.00;
input double BasketLoss               = 100.00;
input int    SpreadLimit              = 100;
input int    WaitSeconds              = 0;
input double FirstStep                = 160.0;
input double MiniGrid1                = 250.0;
input double SmartGrid1               = 80.0;
input double RecoveryMinDistance      = 110.0;
input double MiniGrid2                = 80.0;
input double SmartGrid2               = 60.0;
input double PendingStepTrail         = 50.0;
input double BasketRestartStep        = 160.0;
input int    MaxTrades                = 2000;
input bool   EnableCloseBy            = false;
input double BuyProgressionTolerance  = 10.0;

string EA_NAME = "EAGOLD";

double PointsToPrice(double points){ return(points * Point); }
double NormalizePrice(double price){ return(NormalizeDouble(price, Digits)); }
double NormalizeLot(double lot)
{
   if(lot < Lot) lot = Lot;
   if(MaxOpenLot > 0.0 && lot > MaxOpenLot) lot = MaxOpenLot;
   return(NormalizeDouble(lot, DigitsLots));
}
bool IsEAGOLDOrder(){ return(OrderSymbol() == Symbol() && OrderMagicNumber() == MagicNumber); }
double CurrentSpreadPrice(){ RefreshRates(); return(Ask - Bid); }

int CountOrdersByType(int type)
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
int CountDirectionPositions(int direction){ return(CountOrdersByType(direction==OP_BUY?OP_BUY:OP_SELL)); }
int CountDirectionPending(int direction){ return(CountOrdersByType(direction==OP_BUY?OP_BUYSTOP:OP_SELLSTOP); }
int CountEAGOLDOrders()
{
   int count=0;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(IsEAGOLDOrder()) count++;
   }
   return(count);
}

double DirectionBasketProfit(int direction)
{
   int type=(direction==OP_BUY?OP_BUY:OP_SELL);
   double total=0.0;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(!IsEAGOLDOrder() || OrderType()!=type) continue;
      total+=OrderProfit();
   }
   return(total);
}

double TotalEAGOLDFloatingProfit()
{
   double total=0.0;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(!IsEAGOLDOrder()) continue;
      int type=OrderType();
      if(type==OP_BUY || type==OP_SELL) total+=OrderProfit();
   }
   return(total);
}

int SendPending(int type,double price,double lots,string comment)
{
   RefreshRates();
   double stopLevel=MarketInfo(Symbol(),MODE_STOPLEVEL)*Point;
   price=NormalizePrice(price);
   lots=NormalizeLot(lots);
   if(type==OP_BUYSTOP && price<=Ask+stopLevel) return(-1);
   if(type==OP_SELLSTOP && price>=Bid-stopLevel) return(-1);
   ResetLastError();
   int ticket=OrderSend(Symbol(),type,lots,price,0,0,0,comment,MagicNumber,0,clrNONE);
   if(ticket<0)
      Print(EA_NAME," OrderSend failed. type=",type," price=",DoubleToString(price,Digits)," lot=",DoubleToString(lots,DigitsLots)," comment=",comment," error=",GetLastError());
   else
      Print(EA_NAME," pending created. ticket=",ticket," type=",type," price=",DoubleToString(price,Digits)," lot=",DoubleToString(lots,DigitsLots)," comment=",comment);
   return(ticket);
}

bool DeletePendingOrder(int ticket)
{
   if(!OrderSelect(ticket,SELECT_BY_TICKET,MODE_TRADES)) return(false);
   if(!IsEAGOLDOrder()) return(false);
   int type=OrderType();
   if(type!=OP_BUYSTOP && type!=OP_SELLSTOP) return(false);
   ResetLastError();
   if(!OrderDelete(ticket))
   {
      Print(EA_NAME," pending delete failed. ticket=",ticket," error=",GetLastError());
      return(false);
   }
   return(true);
}

bool CloseMarketOrder(int ticket)
{
   if(!OrderSelect(ticket,SELECT_BY_TICKET,MODE_TRADES)) return(false);
   if(!IsEAGOLDOrder()) return(false);
   int type=OrderType();
   if(type!=OP_BUY && type!=OP_SELL) return(false);
   RefreshRates();
   double price=(type==OP_BUY?Bid:Ask);
   ResetLastError();
   if(!OrderClose(ticket,OrderLots(),NormalizePrice(price),0,clrNONE))
   {
      Print(EA_NAME," market close failed. ticket=",ticket," type=",type," error=",GetLastError());
      return(false);
   }
   return(true);
}

// ============================================================
// RULE 1 - FIRST STOP ORDERS / CYCLE INITIALIZATION
// The initial ZEUS observation shows a BUY STOP and a SELL STOP
// created together when the system is completely flat. However,
// BUY and SELL are independent machines after that initialization.
// A missing direction is NOT recreated merely because the opposite
// direction remains active. This allows a valid state such as:
//   BUY positions > 0 and SELL positions = 0
// The initial pair is only created again when the entire EAGOLD
// system is completely flat.
// ============================================================
void CreateFirstOrdersIfFlat()
{
   if(CountEAGOLDOrders()!=0) return;
   RefreshRates();
   int buyTicket=SendPending(OP_BUYSTOP,Ask+PointsToPrice(FirstStep),Lot,"EAGOLD R1 FIRST BUY");
   int sellTicket=SendPending(OP_SELLSTOP,Bid-PointsToPrice(FirstStep),Lot,"EAGOLD R1 FIRST SELL");
   if(buyTicket>0 || sellTicket>0)
      Print(EA_NAME," RULE 1: initial independent BUY/SELL machine seeds created. BUY ticket=",buyTicket," SELL ticket=",sellTicket);
}

// ============================================================
// RULE 2 + RULE 3 - RECOVERY
// R2 confirmed from ZEUS SELL-side history/ticks:
//   distance = current Bid - last activated SELL price
//   trigger when distance >= 2 x SmartGrid1
//   recovery SELL STOP = current Bid - RecoveryMinDistance
// BUY is the directional mirror pending independent BUY-side confirmation.
// RecoveryMinDistance corresponds to ZEUS MinDistance; latest controlled
// ZEUS test used MinDistance=110. No explicit spread subtraction is used.
// ============================================================
bool GetLatestActivatedPosition(int direction,double &latestPrice,double &latestLot,int &latestTicket)
{
   int type=(direction==OP_BUY?OP_BUY:OP_SELL);
   latestPrice=0.0;
   latestLot=NormalizeLot(Lot);
   latestTicket=-1;
   datetime latestTime=0;
   bool found=false;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(!IsEAGOLDOrder() || OrderType()!=type) continue;
      datetime t=OrderOpenTime();
      int ticket=OrderTicket();
      if(!found || t>latestTime || (t==latestTime && ticket>latestTicket))
      {
         found=true;
         latestTime=t;
         latestPrice=OrderOpenPrice();
         latestLot=OrderLots();
         latestTicket=ticket;
      }
   }
   return(found);
}

bool HasRecoveryPending(int direction)
{
   string tag=(direction==OP_BUY?"EAGOLD BUY RECOVERY":"EAGOLD SELL RECOVERY");
   int type=(direction==OP_BUY?OP_BUYSTOP:OP_SELLSTOP);
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(!IsEAGOLDOrder() || OrderType()!=type) continue;
      if(StringFind(OrderComment(),tag,0)>=0) return(true);
   }
   return(false);
}

double NextRecoveryLot(double previousLot)
{
   if(previousLot<=0.0) return(NormalizeLot(Lot));
   return(NormalizeLot(previousLot*Multiplier+LotIncrement));
}

void BuyRecovery()
{
   if(SmartGrid1<=0.0 || RecoveryMinDistance<=0.0) return;
   if(CountDirectionPositions(OP_BUY)<=0) return;
   if(HasRecoveryPending(OP_BUY)) return;
   double lastPrice=0.0,lastLot=NormalizeLot(Lot); int lastTicket=-1;
   if(!GetLatestActivatedPosition(OP_BUY,lastPrice,lastLot,lastTicket)) return;
   RefreshRates();
   double distance=lastPrice-Ask;
   double requiredDistance=PointsToPrice(2.0*SmartGrid1);
   if(distance<requiredDistance) return;
   double newStop=NormalizePrice(Ask+PointsToPrice(RecoveryMinDistance));
   double stopLevel=MarketInfo(Symbol(),MODE_STOPLEVEL)*Point;
   if(newStop<=Ask+stopLevel) return;
   double nextLot=NextRecoveryLot(lastLot);
   Print(EA_NAME," BUY R2/R3 AUTHORIZED. lastTicket=",lastTicket,
         " lastPrice=",DoubleToString(lastPrice,Digits)," lastLot=",DoubleToString(lastLot,DigitsLots),
         " Bid=",DoubleToString(Bid,Digits)," Ask=",DoubleToString(Ask,Digits),
         " distance=",DoubleToString(distance,Digits)," required=",DoubleToString(requiredDistance,Digits),
         " recoveryDistance=",DoubleToString(RecoveryMinDistance,Digits),
         " stop=",DoubleToString(newStop,Digits)," nextLot=",DoubleToString(nextLot,DigitsLots));
   SendPending(OP_BUYSTOP,newStop,nextLot,"EAGOLD BUY RECOVERY");
}

void SellRecovery()
{
   if(SmartGrid1<=0.0 || RecoveryMinDistance<=0.0) return;
   if(CountDirectionPositions(OP_SELL)<=0) return;
   if(HasRecoveryPending(OP_SELL)) return;
   double lastPrice=0.0,lastLot=NormalizeLot(Lot); int lastTicket=-1;
   if(!GetLatestActivatedPosition(OP_SELL,lastPrice,lastLot,lastTicket)) return;
   RefreshRates();
   double distance=Bid-lastPrice;
   double requiredDistance=PointsToPrice(2.0*SmartGrid1);
   if(distance<requiredDistance) return;
   double newStop=NormalizePrice(Bid-PointsToPrice(RecoveryMinDistance));
   double stopLevel=MarketInfo(Symbol(),MODE_STOPLEVEL)*Point;
   if(newStop>=Bid-stopLevel) return;
   double nextLot=NextRecoveryLot(lastLot);
   Print(EA_NAME," SELL R2/R3 AUTHORIZED. lastTicket=",lastTicket,
         " lastPrice=",DoubleToString(lastPrice,Digits)," lastLot=",DoubleToString(lastLot,DigitsLots),
         " Bid=",DoubleToString(Bid,Digits)," Ask=",DoubleToString(Ask,Digits),
         " distance=",DoubleToString(distance,Digits)," required=",DoubleToString(requiredDistance,Digits),
         " recoveryDistance=",DoubleToString(RecoveryMinDistance,Digits),
         " stop=",DoubleToString(newStop,Digits)," nextLot=",DoubleToString(nextLot,DigitsLots));
   SendPending(OP_SELLSTOP,newStop,nextLot,"EAGOLD SELL RECOVERY");
}

// ============================================================
// RULE 6 - RECOVERY STOP TRAILING
// ZEUS evidence: StepTrallOrders=50 is the minimum movement; the
// recovery STOP tracks price at MinDistance. R2 trigger remains based
// on 2 x SmartGrid1. Thus R6 uses RecoveryMinDistance as the trailing
// distance, not 2 x SmartGrid1.
// ============================================================
void TrailRecoveryStopOrders()
{
   if(RecoveryMinDistance<=0.0 || PendingStepTrail<=0.0) return;
   double trailDistance=PointsToPrice(RecoveryMinDistance);
   double trailStep=PointsToPrice(PendingStepTrail);
   double stopLevel=MarketInfo(Symbol(),MODE_STOPLEVEL)*Point;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(!IsEAGOLDOrder()) continue;
      int type=OrderType();
      if(type!=OP_BUYSTOP && type!=OP_SELLSTOP) continue;
      string comment=OrderComment();
      if(StringFind(comment,"EAGOLD BUY RECOVERY",0)<0 && StringFind(comment,"EAGOLD SELL RECOVERY",0)<0) continue;
      RefreshRates();
      double current=OrderOpenPrice();
      double desired=current;
      double movement=0.0;
      if(type==OP_SELLSTOP)
      {
         double distance=Bid-current;
         if(distance<=trailDistance) continue;
         desired=NormalizePrice(Bid-trailDistance);
         movement=desired-current;
         if(movement<trailStep || desired<=current || desired>=Bid-stopLevel) continue;
      }
      else
      {
         double distance=current-Ask;
         if(distance<=trailDistance) continue;
         desired=NormalizePrice(Ask+trailDistance);
         movement=current-desired;
         if(movement<trailStep || desired>=current || desired<=Ask+stopLevel) continue;
      }
      int ticket=OrderTicket();
      ResetLastError();
      if(!OrderModify(ticket,desired,0,0,0,clrNONE))
         Print(EA_NAME," RULE 6: STOP TRAIL FAILED. ticket=",ticket," error=",GetLastError());
      else
         Print(EA_NAME," RULE 6: STOP TRAIL. ticket=",ticket," from=",DoubleToString(current,Digits)," to=",DoubleToString(desired,Digits));
   }
}

// ============================================================
// RULE 7 - R1 FIRST STOP TRAILING
// ============================================================
void TrailR1FirstStopOrders()
{
   if(FirstStep<=0.0 || PendingStepTrail<=0.0) return;
   double trailDistance=PointsToPrice(FirstStep);
   double trailStep=PointsToPrice(PendingStepTrail);
   double activationDistance=trailDistance+trailStep;
   double stopLevel=MarketInfo(Symbol(),MODE_STOPLEVEL)*Point;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(!IsEAGOLDOrder()) continue;
      int type=OrderType();
      if(type!=OP_BUYSTOP && type!=OP_SELLSTOP) continue;
      string comment=OrderComment();
      if(type==OP_BUYSTOP && StringFind(comment,"EAGOLD R1 FIRST BUY",0)<0) continue;
      if(type==OP_SELLSTOP && StringFind(comment,"EAGOLD R1 FIRST SELL",0)<0) continue;
      RefreshRates();
      double current=OrderOpenPrice();
      double desired=current;
      double movement=0.0;
      if(type==OP_SELLSTOP)
      {
         double distance=Bid-current;
         if(distance<activationDistance) continue;
         desired=NormalizePrice(Bid-trailDistance);
         movement=desired-current;
         if(movement<trailStep || desired<=current || desired>=Bid-stopLevel) continue;
      }
      else
      {
         double distance=current-Ask;
         if(distance<activationDistance) continue;
         desired=NormalizePrice(Ask+trailDistance);
         movement=current-desired;
         if(movement<trailStep || desired>=current || desired<=Ask+stopLevel) continue;
      }
      int ticket=OrderTicket();
      ResetLastError();
      if(!OrderModify(ticket,desired,0,0,0,clrNONE))
         Print(EA_NAME," RULE 7: R1 STOP TRAIL FAILED. ticket=",ticket," error=",GetLastError());
      else
         Print(EA_NAME," RULE 7: R1 STOP TRAIL. ticket=",ticket," from=",DoubleToString(current,Digits)," to=",DoubleToString(desired,Digits));
   }
}

// ============================================================
// RULE 4 - SINGLE POSITION TAKE PROFIT / REENTRY
// MiniGrid1 remains the R4 reentry distance. It is intentionally
// separate from RecoveryMinDistance, which models ZEUS MinDistance.
// ============================================================
void BuyCreateReentryAfterSingleTP(){ RefreshRates(); SendPending(OP_BUYSTOP,Ask+PointsToPrice(MiniGrid1),Lot,"EAGOLD BUY TP REENTRY"); }
void SellCreateReentryAfterSingleTP(){ RefreshRates(); SendPending(OP_SELLSTOP,Bid-PointsToPrice(MiniGrid1),Lot,"EAGOLD SELL TP REENTRY"); }

void BuySingleTakeProfit()
{
   if(CountDirectionPositions(OP_BUY)!=1) return;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(!IsEAGOLDOrder() || OrderType()!=OP_BUY) continue;
      if(OrderProfit()<TakeProfit) continue;
      int ticket=OrderTicket();
      if(CloseMarketOrder(ticket)) BuyCreateReentryAfterSingleTP();
      return;
   }
}
void SellSingleTakeProfit()
{
   if(CountDirectionPositions(OP_SELL)!=1) return;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(!IsEAGOLDOrder() || OrderType()!=OP_SELL) continue;
      if(OrderProfit()<TakeProfit) continue;
      int ticket=OrderTicket();
      if(CloseMarketOrder(ticket)) SellCreateReentryAfterSingleTP();
      return;
   }
}

// ============================================================
// RULE 5 - BASKET CLOSE
// Confirmed basket threshold: number of positions x TakeProfit.
// Experimental hedge gate: do not realize one winning basket while
// total floating EAGOLD profit remains negative.
// ============================================================
void CloseAllDirectionPending(int direction)
{
   int type=(direction==OP_BUY?OP_BUYSTOP:OP_SELLSTOP);
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(!IsEAGOLDOrder() || OrderType()!=type) continue;
      DeletePendingOrder(OrderTicket());
   }
}

bool HedgeGateAllowsBasketClose()
{
   double total=TotalEAGOLDFloatingProfit();
   return(total>=0.0);
}

// ============================================================
// RULE 8 - BASKET RESTART
// If a directional basket is completely closed, immediately create
// a new STOP order for that same direction. The opposite machine is
// irrelevant: a BUY basket may restart while SELL positions remain,
// and vice versa.
// BasketRestartStep is intentionally independent from FirstStep,
// MiniGrid1 and RecoveryMinDistance.
// ============================================================
void RestartEmptyBasket(int direction)
{
   if(BasketRestartStep<=0.0) return;
   if(CountDirectionPositions(direction)>0) return;
   if(CountDirectionPending(direction)>0) return;

   RefreshRates();
   int ticket=-1;
   if(direction==OP_BUY)
   {
      double price=NormalizePrice(Ask+PointsToPrice(BasketRestartStep));
      ticket=SendPending(OP_BUYSTOP,price,Lot,"EAGOLD R8 BUY BASKET RESTART");
   }
   else
   {
      double price=NormalizePrice(Bid-PointsToPrice(BasketRestartStep));
      ticket=SendPending(OP_SELLSTOP,price,Lot,"EAGOLD R8 SELL BASKET RESTART");
   }

   if(ticket>0)
      Print(EA_NAME," RULE 8: empty ",direction==OP_BUY?"BUY":"SELL"," basket restarted. ticket=",ticket," step=",DoubleToString(BasketRestartStep,Digits));
}

void BuyBasketClose()
{
   int count=CountDirectionPositions(OP_BUY);
   if(count<=1) return;
   double target=count*TakeProfit;
   if(DirectionBasketProfit(OP_BUY)<target) return;
   if(!HedgeGateAllowsBasketClose())
   {
      Print(EA_NAME," RULE 5: BUY basket target reached but hedge gate blocked close. BuyProfit=",DoubleToString(DirectionBasketProfit(OP_BUY),2)," TotalFloating=",DoubleToString(TotalEAGOLDFloatingProfit(),2));
      return;
   }
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(!IsEAGOLDOrder() || OrderType()!=OP_BUY) continue;
      CloseMarketOrder(OrderTicket());
   }
   CloseAllDirectionPending(OP_BUY);
   RestartEmptyBasket(OP_BUY);
}

void SellBasketClose()
{
   int count=CountDirectionPositions(OP_SELL);
   if(count<=1) return;
   double target=count*TakeProfit;
   if(DirectionBasketProfit(OP_SELL)<target) return;
   if(!HedgeGateAllowsBasketClose())
   {
      Print(EA_NAME," RULE 5: SELL basket target reached but hedge gate blocked close. SellProfit=",DoubleToString(DirectionBasketProfit(OP_SELL),2)," TotalFloating=",DoubleToString(TotalEAGOLDFloatingProfit(),2));
      return;
   }
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(!IsEAGOLDOrder() || OrderType()!=OP_SELL) continue;
      CloseMarketOrder(OrderTicket());
   }
   CloseAllDirectionPending(OP_SELL);
   RestartEmptyBasket(OP_SELL);
}

// ============================================================
// MACHINES
// BUY and SELL execute independently. Neither machine requires an
// open market position on the opposite side to continue operating.
// ============================================================
void BuyMachine(){ BuyBasketClose(); BuySingleTakeProfit(); BuyRecovery(); }
void SellMachine(){ SellBasketClose(); SellSingleTakeProfit(); SellRecovery(); }

int OnInit()
{
   Print(EA_NAME," v0.064 initialized. BUY/SELL machines independent after initial seed. R2 trigger=2x SmartGrid1; RecoveryMinDistance=",DoubleToString(RecoveryMinDistance,Digits),"; R6 trail distance=RecoveryMinDistance; R5 hedge gate=TOTAL>=0; R8 BasketRestartStep=",DoubleToString(BasketRestartStep,Digits));
   CreateFirstOrdersIfFlat();
   return(INIT_SUCCEEDED);
}

void OnTick()
{
   BuyMachine();
   SellMachine();
   CreateFirstOrdersIfFlat();
   TrailRecoveryStopOrders();
   TrailR1FirstStopOrders();
}
