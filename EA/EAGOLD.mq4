#property strict
#property version   "0.067"
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
int CountDirectionPending(int direction){ return(CountOrdersByType(direction==OP_BUY?OP_BUYSTOP:OP_SELLSTOP)); }
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

void CreateFirstOrdersIfFlat()
{
   if(CountEAGOLDOrders()!=0) return;
   RefreshRates();
   int buyTicket=SendPending(OP_BUYSTOP,Ask+PointsToPrice(FirstStep),Lot,"EAGOLD R1 FIRST BUY");
   int sellTicket=SendPending(OP_SELLSTOP,Bid-PointsToPrice(FirstStep),Lot,"EAGOLD R1 FIRST SELL");
   if(buyTicket>0 || sellTicket>0)
      Print(EA_NAME," RULE 1: initial BUY/SELL seeds created. BUY ticket=",buyTicket," SELL ticket=",sellTicket);
}

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
         found=true; latestTime=t; latestPrice=OrderOpenPrice(); latestLot=OrderLots(); latestTicket=ticket;
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
   if(CountDirectionPositions(OP_BUY)<=0 || HasRecoveryPending(OP_BUY)) return;
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
   SendPending(OP_BUYSTOP,newStop,nextLot,"EAGOLD BUY RECOVERY");
}

void SellRecovery()
{
   if(SmartGrid1<=0.0 || RecoveryMinDistance<=0.0) return;
   if(CountDirectionPositions(OP_SELL)<=0 || HasRecoveryPending(OP_SELL)) return;
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
   SendPending(OP_SELLSTOP,newStop,nextLot,"EAGOLD SELL RECOVERY");
}

// RULE 6 - TRAILING OF ORDINARY STOP ORDERS.
// Applies to non-special STOPs: recovery, TP reentry and other normal pending orders.
// SELL STOP can only move upward; BUY STOP can only move downward.
// Trigger distance: 2 x SmartGrid1.
// Trailing distance: RecoveryMinDistance (ZEUS MinDistance).
// Minimum favorable movement between modifications: PendingStepTrail.
void TrailStopOrdersRule6()
{
   if(SmartGrid1<=0.0 || RecoveryMinDistance<=0.0 || PendingStepTrail<=0.0) return;
   double triggerDistance=PointsToPrice(2.0*SmartGrid1);
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
      if(StringFind(comment,"EAGOLD R1 FIRST BUY",0)>=0) continue;
      if(StringFind(comment,"EAGOLD R1 FIRST SELL",0)>=0) continue;
      if(StringFind(comment,"EAGOLD R7 FIRST BUY",0)>=0) continue;
      if(StringFind(comment,"EAGOLD R7 FIRST SELL",0)>=0) continue;
      if(StringFind(comment,"EAGOLD R7 RESTART BUY",0)>=0) continue;
      if(StringFind(comment,"EAGOLD R7 RESTART SELL",0)>=0) continue;

      RefreshRates();
      double current=OrderOpenPrice();
      double desired=current;
      double movement=0.0;

      if(type==OP_SELLSTOP)
      {
         double distance=Bid-current;
         if(distance<triggerDistance) continue;
         desired=NormalizePrice(Bid-trailDistance);
         movement=desired-current;
         if(movement<trailStep || desired<=current || desired>=Bid-stopLevel) continue;
      }
      else
      {
         double distance=current-Ask;
         if(distance<triggerDistance) continue;
         desired=NormalizePrice(Ask+trailDistance);
         movement=current-desired;
         if(movement<trailStep || desired>=current || desired<=Ask+stopLevel) continue;
      }

      int ticket=OrderTicket();
      ResetLastError();
      if(!OrderModify(ticket,desired,0,0,0,clrNONE))
         Print(EA_NAME," RULE 6: STOP TRAIL FAILED. ticket=",ticket," comment=",comment," error=",GetLastError());
      else
         Print(EA_NAME," RULE 6: STOP TRAIL. ticket=",ticket," comment=",comment," from=",DoubleToString(current,Digits)," to=",DoubleToString(desired,Digits));
   }
}

// RULE 7 - SPECIAL TRAILING OF THE FIRST STOP.
// This rule applies to TWO situations:
// 1) the original first BUY/SELL STOP created by Rule 1;
// 2) the first STOP created immediately after a directional basket is closed (Rule 8).
// These special STOPs use FirstStep as trailing distance and PendingStepTrail as
// the minimum favorable movement. They are intentionally excluded from Rule 6.
void TrailSpecialFirstStopOrders()
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
      bool special=false;
      if(StringFind(comment,"EAGOLD R1 FIRST BUY",0)>=0) special=true;
      if(StringFind(comment,"EAGOLD R1 FIRST SELL",0)>=0) special=true;
      if(StringFind(comment,"EAGOLD R7 FIRST BUY",0)>=0) special=true;
      if(StringFind(comment,"EAGOLD R7 FIRST SELL",0)>=0) special=true;
      if(StringFind(comment,"EAGOLD R7 RESTART BUY",0)>=0) special=true;
      if(StringFind(comment,"EAGOLD R7 RESTART SELL",0)>=0) special=true;
      if(!special) continue;

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
         Print(EA_NAME," RULE 7: SPECIAL STOP TRAIL FAILED. ticket=",ticket," comment=",comment," error=",GetLastError());
      else
         Print(EA_NAME," RULE 7: SPECIAL STOP TRAIL. ticket=",ticket," comment=",comment," from=",DoubleToString(current,Digits)," to=",DoubleToString(desired,Digits));
   }
}

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

bool HedgeGateAllowsBasketClose(){ return(TotalEAGOLDFloatingProfit()>=0.0); }

bool BuyBasketClose()
{
   int count=CountDirectionPositions(OP_BUY);
   if(count<=1) return(false);
   double target=count*TakeProfit;
   if(DirectionBasketProfit(OP_BUY)<target || !HedgeGateAllowsBasketClose()) return(false);
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(!IsEAGOLDOrder() || OrderType()!=OP_BUY) continue;
      CloseMarketOrder(OrderTicket());
   }
   if(CountDirectionPositions(OP_BUY)>0) return(false);
   CloseAllDirectionPending(OP_BUY);
   return(true);
}

bool SellBasketClose()
{
   int count=CountDirectionPositions(OP_SELL);
   if(count<=1) return(false);
   double target=count*TakeProfit;
   if(DirectionBasketProfit(OP_SELL)<target || !HedgeGateAllowsBasketClose()) return(false);
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(!IsEAGOLDOrder() || OrderType()!=OP_SELL) continue;
      CloseMarketOrder(OrderTicket());
   }
   if(CountDirectionPositions(OP_SELL)>0) return(false);
   CloseAllDirectionPending(OP_SELL);
   return(true);
}

void RestartEmptyBasket(int direction)
{
   if(BasketRestartStep<=0.0) return;
   if(CountDirectionPositions(direction)!=0) return;
   if(CountDirectionPending(direction)!=0) return;

   RefreshRates();
   if(direction==OP_BUY)
   {
      double price=NormalizePrice(Ask+PointsToPrice(BasketRestartStep));
      Print(EA_NAME," RULE 8: BUY basket closed and empty. Creating R7 special BUY STOP at ",DoubleToString(price,Digits));
      SendPending(OP_BUYSTOP,price,Lot,"EAGOLD R7 RESTART BUY");
   }
   else
   {
      double price=NormalizePrice(Bid-PointsToPrice(BasketRestartStep));
      Print(EA_NAME," RULE 8: SELL basket closed and empty. Creating R7 special SELL STOP at ",DoubleToString(price,Digits));
      SendPending(OP_SELLSTOP,price,Lot,"EAGOLD R7 RESTART SELL");
   }
}

void BuyMachine()
{
   bool basketClosed=BuyBasketClose();
   if(basketClosed) RestartEmptyBasket(OP_BUY);
   BuySingleTakeProfit();
   BuyRecovery();
}

void SellMachine()
{
   bool basketClosed=SellBasketClose();
   if(basketClosed) RestartEmptyBasket(OP_SELL);
   SellSingleTakeProfit();
   SellRecovery();
}

int OnInit()
{
   Print(EA_NAME," v0.067 initialized. R6=ordinary STOPs; R7=R1 first STOP + first STOP after basket restart; R7 trail=FirstStep; step=PendingStepTrail.");
   CreateFirstOrdersIfFlat();
   return(INIT_SUCCEEDED);
}

void OnTick()
{
   BuyMachine();
   SellMachine();
   CreateFirstOrdersIfFlat();
   TrailStopOrdersRule6();
   TrailSpecialFirstStopOrders();
}