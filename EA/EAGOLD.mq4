#property strict
#property version   "0.050"
#property description "EAGOLD - BUY/SELL independent machines - Rules 1 to 7"

input int    MagicNumber              = 1001;
input double Lot                      = 0.01;
input double Multiplier               = 1.10;
input int    DigitsLots               = 2;
input double LotIncrement             = 0.02;
input double MaxOpenLot               = 3.00;
input double TakeProfit               = 5.00;
input double SellProfit               = 30.00;
input double BasketLoss               = 100.00;
input int    SpreadLimit               = 100;
input int    WaitSeconds               = 0;
input double FirstStep                 = 160.0;
input double MiniGrid1                = 250.0;
input double SmartGrid1               = 80.0;
input double MiniGrid2                = 80.0;
input double SmartGrid2               = 60.0;
input double PendingStepTrail         = 50.0;
input int    MaxTrades                = 2000;
input bool   EnableCloseBy            = false;
input double BuyProgressionTolerance  = 10.0;

string EA_NAME = "EAGOLD";
bool BuyInitialCycleStarted = false;
bool SellInitialCycleStarted = false;

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
   int count = 0;
   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsEAGOLDOrder()) continue;
      if(OrderType() == type) count++;
   }
   return(count);
}
int CountDirectionPositions(int direction){ return(CountOrdersByType(direction == OP_BUY ? OP_BUY : OP_SELL)); }
int CountDirectionPending(int direction){ return(CountOrdersByType(direction == OP_BUY ? OP_BUYSTOP : OP_SELLSTOP)); }

double DirectionBasketProfit(int direction)
{
   int type = (direction == OP_BUY ? OP_BUY : OP_SELL);
   double total = 0.0;
   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsEAGOLDOrder() || OrderType() != type) continue;
      total += OrderProfit();
   }
   return(total);
}

int SendPending(int type, double price, double lots, string comment)
{
   RefreshRates();
   double stopLevel = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;
   price = NormalizePrice(price);
   lots = NormalizeLot(lots);
   if(type == OP_BUYSTOP && price <= Ask + stopLevel) return(-1);
   if(type == OP_SELLSTOP && price >= Bid - stopLevel) return(-1);
   ResetLastError();
   int ticket = OrderSend(Symbol(), type, lots, price, 0, 0, 0, comment, MagicNumber, 0, clrNONE);
   if(ticket < 0)
      Print(EA_NAME, " OrderSend failed. type=", type, " price=", DoubleToString(price, Digits), " lot=", DoubleToString(lots, DigitsLots), " comment=", comment, " error=", GetLastError());
   else
      Print(EA_NAME, " pending created. ticket=", ticket, " type=", type, " price=", DoubleToString(price, Digits), " lot=", DoubleToString(lots, DigitsLots), " comment=", comment);
   return(ticket);
}

bool DeletePendingOrder(int ticket)
{
   if(!OrderSelect(ticket, SELECT_BY_TICKET, MODE_TRADES)) return(false);
   if(!IsEAGOLDOrder()) return(false);
   int type = OrderType();
   if(type != OP_BUYSTOP && type != OP_SELLSTOP) return(false);
   ResetLastError();
   if(!OrderDelete(ticket))
   {
      Print(EA_NAME, " pending delete failed. ticket=", ticket, " error=", GetLastError());
      return(false);
   }
   return(true);
}

bool CloseMarketOrder(int ticket)
{
   if(!OrderSelect(ticket, SELECT_BY_TICKET, MODE_TRADES)) return(false);
   if(!IsEAGOLDOrder()) return(false);
   int type = OrderType();
   if(type != OP_BUY && type != OP_SELL) return(false);
   RefreshRates();
   double price = (type == OP_BUY ? Bid : Ask);
   ResetLastError();
   if(!OrderClose(ticket, OrderLots(), NormalizePrice(price), 0, clrNONE))
   {
      Print(EA_NAME, " market close failed. ticket=", ticket, " type=", type, " error=", GetLastError());
      return(false);
   }
   return(true);
}

// ============================================================
// RULE 1 - FIRST STOP ORDERS
// R1 uses FirstStep. MiniGrid1 is not used for first orders.
// ============================================================
void BuyCreateFirstOrder()
{
   if(BuyInitialCycleStarted) return;
   if(CountDirectionPositions(OP_BUY) > 0) return;
   if(CountDirectionPending(OP_BUY) > 0) return;
   RefreshRates();
   int ticket = SendPending(OP_BUYSTOP, Ask + PointsToPrice(FirstStep), Lot, "EAGOLD FIRST BUY");
   if(ticket > 0) BuyInitialCycleStarted = true;
}

void SellCreateFirstOrder()
{
   if(SellInitialCycleStarted) return;
   if(CountDirectionPositions(OP_SELL) > 0) return;
   if(CountDirectionPending(OP_SELL) > 0) return;
   RefreshRates();
   int ticket = SendPending(OP_SELLSTOP, Bid - PointsToPrice(FirstStep), Lot, "EAGOLD FIRST SELL");
   if(ticket > 0) SellInitialCycleStarted = true;
}

// ============================================================
// RULE 2 + RULE 3 - RECOVERY
// ============================================================
bool GetLatestActivatedPosition(int direction, double &latestPrice, double &latestLot, int &latestTicket)
{
   int type = (direction == OP_BUY ? OP_BUY : OP_SELL);
   latestPrice = 0.0;
   latestLot = NormalizeLot(Lot);
   latestTicket = -1;
   datetime latestTime = 0;
   bool found = false;
   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsEAGOLDOrder() || OrderType() != type) continue;
      datetime t = OrderOpenTime();
      int ticket = OrderTicket();
      if(!found || t > latestTime || (t == latestTime && ticket > latestTicket))
      {
         found = true;
         latestTime = t;
         latestPrice = OrderOpenPrice();
         latestLot = OrderLots();
         latestTicket = ticket;
      }
   }
   return(found);
}

double NextRecoveryLot(double previousLot)
{
   if(previousLot <= 0.0) return(NormalizeLot(Lot));
   return(NormalizeLot((previousLot * Multiplier) + LotIncrement));
}

void BuyRecovery()
{
   if(SmartGrid1 <= 0.0) return;
   if(CountDirectionPositions(OP_BUY) <= 0) return;
   if(CountDirectionPending(OP_BUY) > 0) return;
   double lastPrice=0.0, lastLot=NormalizeLot(Lot);
   int lastTicket=-1;
   if(!GetLatestActivatedPosition(OP_BUY, lastPrice, lastLot, lastTicket)) return;
   RefreshRates();
   double trigger = NormalizePrice(lastPrice - PointsToPrice(2.0 * SmartGrid1));
   if(Bid >= trigger) return;
   double newStop = NormalizePrice(lastPrice - PointsToPrice(SmartGrid1));
   double stopLevel = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;
   if(newStop <= Ask + stopLevel) return;
   double nextLot = NextRecoveryLot(lastLot);
   Print(EA_NAME, " BUY R2/R3 AUTHORIZED. lastTicket=", lastTicket, " lastPrice=", DoubleToString(lastPrice, Digits), " lastLot=", DoubleToString(lastLot, DigitsLots), " trigger=", DoubleToString(trigger, Digits), " Bid=", DoubleToString(Bid, Digits), " stop=", DoubleToString(newStop, Digits), " nextLot=", DoubleToString(nextLot, DigitsLots));
   SendPending(OP_BUYSTOP, newStop, nextLot, "EAGOLD BUY RECOVERY");
}

void SellRecovery()
{
   if(SmartGrid1 <= 0.0) return;
   if(CountDirectionPositions(OP_SELL) <= 0) return;
   if(CountDirectionPending(OP_SELL) > 0) return;
   double lastPrice=0.0, lastLot=NormalizeLot(Lot);
   int lastTicket=-1;
   if(!GetLatestActivatedPosition(OP_SELL, lastPrice, lastLot, lastTicket)) return;
   RefreshRates();
   double trigger = NormalizePrice(lastPrice + PointsToPrice(2.0 * SmartGrid1));
   if(Ask <= trigger) return;
   double newStop = NormalizePrice(lastPrice + PointsToPrice(SmartGrid1));
   double stopLevel = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;
   if(newStop >= Bid - stopLevel) return;
   double nextLot = NextRecoveryLot(lastLot);
   Print(EA_NAME, " SELL R2/R3 AUTHORIZED. lastTicket=", lastTicket, " lastPrice=", DoubleToString(lastPrice, Digits), " lastLot=", DoubleToString(lastLot, DigitsLots), " trigger=", DoubleToString(trigger, Digits), " Ask=", DoubleToString(Ask, Digits), " stop=", DoubleToString(newStop, Digits), " nextLot=", DoubleToString(nextLot, DigitsLots));
   SendPending(OP_SELLSTOP, newStop, nextLot, "EAGOLD SELL RECOVERY");
}

// ============================================================
// RULE 6 - TRAILING OF RECOVERY STOP ORDERS ONLY
// R6 remains unchanged: recovery STOP trails after >2x SmartGrid1.
// ============================================================
void TrailRecoveryStopOrders()
{
   if(SmartGrid1 <= 0.0 || PendingStepTrail <= 0.0) return;
   double trailDistance = PointsToPrice(2.0 * SmartGrid1);
   double trailStep = PointsToPrice(PendingStepTrail);
   double stopLevel = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;

   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsEAGOLDOrder()) continue;
      int type = OrderType();
      if(type != OP_BUYSTOP && type != OP_SELLSTOP) continue;

      string comment = OrderComment();
      if(StringFind(comment, "EAGOLD BUY RECOVERY", 0) < 0 &&
         StringFind(comment, "EAGOLD SELL RECOVERY", 0) < 0)
         continue;

      RefreshRates();
      double current = OrderOpenPrice();
      double desired = current;
      double movement = 0.0;

      if(type == OP_SELLSTOP)
      {
         double distance = Bid - current;
         if(distance <= trailDistance) continue;
         desired = NormalizePrice(Bid - trailDistance);
         movement = desired - current;
         if(movement < trailStep || desired <= current || desired >= Bid - stopLevel) continue;
      }
      else
      {
         double distance = current - Ask;
         if(distance <= trailDistance) continue;
         desired = NormalizePrice(Ask + trailDistance);
         movement = current - desired;
         if(movement < trailStep || desired >= current || desired <= Ask + stopLevel) continue;
      }

      int ticket = OrderTicket();
      ResetLastError();
      if(!OrderModify(ticket, desired, 0, 0, 0, clrNONE))
         Print(EA_NAME, " RULE 6: STOP TRAIL FAILED. ticket=", ticket, " error=", GetLastError());
      else
         Print(EA_NAME, " RULE 6: STOP TRAIL. ticket=", ticket, " from=", DoubleToString(current, Digits), " to=", DoubleToString(desired, Digits));
   }
}

// ============================================================
// RULE 7 - TRAILING OF R1 MARKET POSITIONS ONLY
// R7 starts after adverse movement of 1x SmartGrid1 + PendingStepTrail.
// Each additional 1x PendingStepTrail advances the R1 StopLoss by
// exactly 1x PendingStepTrail. The SL remains 1x SmartGrid1 from price.
// ============================================================
void TrailR1Positions()
{
   if(SmartGrid1 <= 0.0 || PendingStepTrail <= 0.0) return;
   double trailDistance = PointsToPrice(SmartGrid1);
   double trailStep = PointsToPrice(PendingStepTrail);
   double activationDistance = trailDistance + trailStep;
   double stopLevel = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;

   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsEAGOLDOrder()) continue;
      int type = OrderType();
      if(type != OP_BUY && type != OP_SELL) continue;

      string comment = OrderComment();
      bool isR1 = false;
      if(type == OP_BUY && StringFind(comment, "EAGOLD FIRST BUY", 0) >= 0) isR1 = true;
      if(type == OP_SELL && StringFind(comment, "EAGOLD FIRST SELL", 0) >= 0) isR1 = true;
      if(!isR1) continue;

      RefreshRates();
      double openPrice = OrderOpenPrice();
      double currentSL = OrderStopLoss();
      double desiredSL = currentSL;

      if(type == OP_BUY)
      {
         double adverseMove = openPrice - Bid;
         if(adverseMove < activationDistance) continue;

         desiredSL = NormalizePrice(Bid + trailDistance);
         if(currentSL > 0.0 && currentSL - desiredSL < trailStep) continue;
         if(desiredSL <= Bid + stopLevel) continue;
         if(currentSL > 0.0 && desiredSL >= currentSL) continue;
      }
      else
      {
         double adverseMove = Ask - openPrice;
         if(adverseMove < activationDistance) continue;

         desiredSL = NormalizePrice(Ask - trailDistance);
         if(currentSL > 0.0 && desiredSL - currentSL < trailStep) continue;
         if(desiredSL >= Ask - stopLevel) continue;
         if(currentSL > 0.0 && desiredSL <= currentSL) continue;
      }

      int ticket = OrderTicket();
      ResetLastError();
      if(!OrderModify(ticket, openPrice, desiredSL, 0, 0, clrNONE))
         Print(EA_NAME, " RULE 7: R1 TRAIL FAILED. ticket=", ticket, " error=", GetLastError());
      else
         Print(EA_NAME, " RULE 7: R1 TRAIL. ticket=", ticket,
               " open=", DoubleToString(openPrice, Digits),
               " sl=", DoubleToString(desiredSL, Digits));
   }
}

// ============================================================
// RULE 4 - SINGLE POSITION TAKE PROFIT + REENTRY
// ============================================================
void BuyCreateReentryAfterSingleTP(){ RefreshRates(); SendPending(OP_BUYSTOP, Ask + PointsToPrice(MiniGrid1), Lot, "EAGOLD BUY TP REENTRY"); }
void SellCreateReentryAfterSingleTP(){ RefreshRates(); SendPending(OP_SELLSTOP, Bid - PointsToPrice(MiniGrid1), Lot, "EAGOLD SELL TP REENTRY"); }

void BuySingleTakeProfit()
{
   if(TakeProfit <= 0.0 || CountDirectionPositions(OP_BUY) != 1) return;
   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsEAGOLDOrder() || OrderType() != OP_BUY) continue;
      double profit = OrderProfit();
      if(profit < TakeProfit) continue;
      int ticket = OrderTicket();
      if(CloseMarketOrder(ticket))
      {
         Print(EA_NAME, " BUY RULE 4: TakeProfit reached. ticket=", ticket, " profit=", DoubleToString(profit, 2));
         BuyCreateReentryAfterSingleTP();
      }
      break;
   }
}

void SellSingleTakeProfit()
{
   if(TakeProfit <= 0.0 || CountDirectionPositions(OP_SELL) != 1) return;
   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsEAGOLDOrder() || OrderType() != OP_SELL) continue;
      double profit = OrderProfit();
      if(profit < TakeProfit) continue;
      int ticket = OrderTicket();
      if(CloseMarketOrder(ticket))
      {
         Print(EA_NAME, " SELL RULE 4: TakeProfit reached. ticket=", ticket, " profit=", DoubleToString(profit, 2));
         SellCreateReentryAfterSingleTP();
      }
      break;
   }
}

// ============================================================
// RULE 5 - BASKET CLOSE
// ============================================================
bool CloseAllDirectionPending(int direction)
{
   int type = (direction == OP_BUY ? OP_BUYSTOP : OP_SELLSTOP);
   bool ok = true;
   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsEAGOLDOrder() || OrderType() != type) continue;
      if(!DeletePendingOrder(OrderTicket())) ok = false;
   }
   return(ok);
}

void BuyBasketClose()
{
   int count = CountDirectionPositions(OP_BUY);
   if(count <= 1 || TakeProfit <= 0.0) return;
   double target = count * TakeProfit;
   if(DirectionBasketProfit(OP_BUY) < target) return;
   Print(EA_NAME, " BUY RULE 5: basket target reached. count=", count, " target=", DoubleToString(target, 2));
   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsEAGOLDOrder() || OrderType() != OP_BUY) continue;
      CloseMarketOrder(OrderTicket());
   }
   CloseAllDirectionPending(OP_BUY);
}

void SellBasketClose()
{
   int count = CountDirectionPositions(OP_SELL);
   if(count <= 1 || TakeProfit <= 0.0) return;
   double target = count * TakeProfit;
   if(DirectionBasketProfit(OP_SELL) < target) return;
   Print(EA_NAME, " SELL RULE 5: basket target reached. count=", count, " target=", DoubleToString(target, 2));
   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsEAGOLDOrder() || OrderType() != OP_SELL) continue;
      CloseMarketOrder(OrderTicket());
   }
   CloseAllDirectionPending(OP_SELL);
}

void BuyMachine(){ BuyBasketClose(); BuySingleTakeProfit(); BuyRecovery(); BuyCreateFirstOrder(); }
void SellMachine(){ SellBasketClose(); SellSingleTakeProfit(); SellRecovery(); SellCreateFirstOrder(); }

int OnInit()
{
   Print(EA_NAME, " v0.050 initialized. R1=FirstStep; R6=R2 recovery STOP trailing; R7=R1 adverse trailing with SmartGrid1+PendingStepTrail activation and PendingStepTrail increments. Multiplier=", DoubleToString(Multiplier,2), " LotIncrement=", DoubleToString(LotIncrement,DigitsLots));
   BuyCreateFirstOrder();
   SellCreateFirstOrder();
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason){}

void OnTick()
{
   // R2/R3/R4/R5 machines execute first.
   // R6 can only trail Recovery STOPs created by R2.
   // R7 independently trails only market positions originating from R1.
   BuyMachine();
   SellMachine();
   TrailRecoveryStopOrders();
   TrailR1Positions();
}
