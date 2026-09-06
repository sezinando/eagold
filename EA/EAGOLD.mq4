#property strict
#property version   "0.040"
#property description "EAGOLD - BUY/SELL independent machines - Rules 1 to 5"

input int    MagicNumber              = 1001;
input double Lot                      = 0.01;
input double Multiplier               = 1.10;
input int    DigitsLots               = 2;
input double LotIncrement             = 0.02; // reserved; not used by Rules 1-5
input double MaxOpenLot               = 3.00;
input double TakeProfit               = 5.00; // monetary
input double SellProfit               = 30.00; // reserved
input double BasketLoss               = 100.00; // reserved
input int    SpreadLimit              = 100; // reserved
input int    WaitSeconds              = 0; // reserved
input double FirstStep                = 160.0; // reserved; Rules 1-5 use MiniGrid1/SmartGrid1
input double MiniGrid1                = 250.0;
input double SmartGrid1               = 80.0;
input double MiniGrid2                = 80.0; // reserved
input double SmartGrid2               = 60.0; // reserved
input double PendingStepTrail         = 50.0; // reserved; recovery STOPs are NOT trailed
input int    MaxTrades                = 2000; // reserved
input bool   EnableCloseBy            = false; // reserved
input double BuyProgressionTolerance  = 10.0; // reserved

string EA_NAME = "EAGOLD";

bool BuyInitialCycleStarted = false;
bool SellInitialCycleStarted = false;

// ============================================================
// COMMON UTILITIES
// ============================================================

double PointsToPrice(double points)
{
   return(points * Point);
}

double NormalizePrice(double price)
{
   return(NormalizeDouble(price, Digits));
}

double NormalizeLot(double lot)
{
   if(lot < Lot) lot = Lot;
   if(MaxOpenLot > 0.0 && lot > MaxOpenLot) lot = MaxOpenLot;
   return(NormalizeDouble(lot, DigitsLots));
}

bool IsEAGOLDOrder()
{
   return(OrderSymbol() == Symbol() && OrderMagicNumber() == MagicNumber);
}

int CountOrdersByType(int type)
{
   int count = 0;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsEAGOLDOrder()) continue;
      if(OrderType() == type) count++;
   }

   return(count);
}

int CountDirectionPositions(int direction)
{
   int type = (direction == OP_BUY ? OP_BUY : OP_SELL);
   return(CountOrdersByType(type));
}

int CountDirectionPending(int direction)
{
   int type = (direction == OP_BUY ? OP_BUYSTOP : OP_SELLSTOP);
   return(CountOrdersByType(type));
}

double DirectionBasketProfit(int direction)
{
   int type = (direction == OP_BUY ? OP_BUY : OP_SELL);
   double total = 0.0;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
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
   lots  = NormalizeLot(lots);

   if(type == OP_BUYSTOP && price <= Ask + stopLevel)
      return(-1);

   if(type == OP_SELLSTOP && price >= Bid - stopLevel)
      return(-1);

   ResetLastError();

   int ticket = OrderSend(Symbol(), type, lots, price, 0, 0, 0,
                          comment, MagicNumber, 0, clrNONE);

   if(ticket < 0)
   {
      Print(EA_NAME,
            " OrderSend failed. type=", type,
            " price=", DoubleToString(price, Digits),
            " lot=", DoubleToString(lots, DigitsLots),
            " comment=", comment,
            " error=", GetLastError());
   }
   else
   {
      Print(EA_NAME,
            " pending created. ticket=", ticket,
            " type=", type,
            " price=", DoubleToString(price, Digits),
            " lot=", DoubleToString(lots, DigitsLots),
            " comment=", comment);
   }

   return(ticket);
}

bool DeletePendingOrder(int ticket)
{
   if(!OrderSelect(ticket, SELECT_BY_TICKET, MODE_TRADES))
      return(false);

   if(!IsEAGOLDOrder())
      return(false);

   int type = OrderType();
   if(type != OP_BUYSTOP && type != OP_SELLSTOP)
      return(false);

   ResetLastError();

   if(!OrderDelete(ticket))
   {
      Print(EA_NAME,
            " pending delete failed. ticket=", ticket,
            " error=", GetLastError());
      return(false);
   }

   return(true);
}

bool CloseMarketOrder(int ticket)
{
   if(!OrderSelect(ticket, SELECT_BY_TICKET, MODE_TRADES))
      return(false);

   if(!IsEAGOLDOrder())
      return(false);

   int type = OrderType();
   if(type != OP_BUY && type != OP_SELL)
      return(false);

   RefreshRates();

   double lots = OrderLots();
   double price = (type == OP_BUY ? Bid : Ask);

   ResetLastError();

   if(!OrderClose(ticket, lots, NormalizePrice(price), 0, clrNONE))
   {
      Print(EA_NAME,
            " market close failed. ticket=", ticket,
            " type=", type,
            " error=", GetLastError());
      return(false);
   }

   return(true);
}

// ============================================================
// RULE 1 - FIRST STOP ORDERS
// ============================================================

void BuyCreateFirstOrder()
{
   if(BuyInitialCycleStarted) return;
   if(CountDirectionPositions(OP_BUY) > 0) return;
   if(CountDirectionPending(OP_BUY) > 0) return;

   RefreshRates();

   double price = NormalizePrice(Ask + PointsToPrice(MiniGrid1));

   int ticket = SendPending(OP_BUYSTOP, price, Lot,
                            "EAGOLD FIRST BUY");

   if(ticket > 0)
      BuyInitialCycleStarted = true;
}

void SellCreateFirstOrder()
{
   if(SellInitialCycleStarted) return;
   if(CountDirectionPositions(OP_SELL) > 0) return;
   if(CountDirectionPending(OP_SELL) > 0) return;

   RefreshRates();

   double price = NormalizePrice(Bid - PointsToPrice(MiniGrid1));

   int ticket = SendPending(OP_SELLSTOP, price, Lot,
                            "EAGOLD FIRST SELL");

   if(ticket > 0)
      SellInitialCycleStarted = true;
}

// ============================================================
// RULE 2 - RECOVERY PROGRESSION
// ============================================================

bool GetLatestActivatedPosition(int direction,
                                double &latestPrice,
                                double &latestLot,
                                int &latestTicket)
{
   int type = (direction == OP_BUY ? OP_BUY : OP_SELL);

   latestPrice = 0.0;
   latestLot = NormalizeLot(Lot);
   latestTicket = -1;

   datetime latestTime = 0;
   bool found = false;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsEAGOLDOrder() || OrderType() != type) continue;

      datetime openTime = OrderOpenTime();
      int ticket = OrderTicket();

      if(!found ||
         openTime > latestTime ||
         (openTime == latestTime && ticket > latestTicket))
      {
         found = true;
         latestTime = openTime;
         latestPrice = OrderOpenPrice();
         latestLot = OrderLots();
         latestTicket = ticket;
      }
   }

   return(found);
}

double NextRecoveryLot(double previousLot)
{
   // RULE 3: multiplier is always applied to the last activated lot.
   return(NormalizeLot(previousLot * Multiplier));
}

void BuyRecovery()
{
   if(SmartGrid1 <= 0.0) return;
   if(CountDirectionPositions(OP_BUY) <= 0) return;

   // Only one pending BUY recovery may exist at a time.
   if(CountDirectionPending(OP_BUY) > 0) return;

   double lastPrice = 0.0;
   double lastLot = NormalizeLot(Lot);
   int lastTicket = -1;

   if(!GetLatestActivatedPosition(OP_BUY, lastPrice, lastLot, lastTicket))
      return;

   RefreshRates();

   // BUY adverse movement = price falling.
   // RULE 2 requires strictly MORE than 2 x SmartGrid1.
   double triggerPrice = NormalizePrice(
      lastPrice - PointsToPrice(2.0 * SmartGrid1));

   if(Bid >= triggerPrice) return;

   // New BUY STOP is one SmartGrid1 below the last activated BUY.
   double newStop = NormalizePrice(
      lastPrice - PointsToPrice(SmartGrid1));

   double stopLevel = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;

   if(newStop <= Ask + stopLevel)
      return;

   double nextLot = NextRecoveryLot(lastLot);

   Print(EA_NAME,
         " BUY RULE 2 TRIGGERED. lastTicket=", lastTicket,
         " lastPrice=", DoubleToString(lastPrice, Digits),
         " lastLot=", DoubleToString(lastLot, DigitsLots),
         " trigger=", DoubleToString(triggerPrice, Digits),
         " Ask=", DoubleToString(Ask, Digits),
         " newBUYStop=", DoubleToString(newStop, Digits),
         " nextLot=", DoubleToString(nextLot, DigitsLots));

   // IMPORTANT: recovery pending is fixed at its business-rule level.
   // It is NOT trailing.
   SendPending(OP_BUYSTOP, newStop, nextLot,
               "EAGOLD BUY RECOVERY");
}

void SellRecovery()
{
   if(SmartGrid1 <= 0.0) return;
   if(CountDirectionPositions(OP_SELL) <= 0) return;

   // Only one pending SELL recovery may exist at a time.
   if(CountDirectionPending(OP_SELL) > 0) return;

   double lastPrice = 0.0;
   double lastLot = NormalizeLot(Lot);
   int lastTicket = -1;

   if(!GetLatestActivatedPosition(OP_SELL, lastPrice, lastLot, lastTicket))
      return;

   RefreshRates();

   // SELL adverse movement = price rising.
   // RULE 2 requires strictly MORE than 2 x SmartGrid1.
   double triggerPrice = NormalizePrice(
      lastPrice + PointsToPrice(2.0 * SmartGrid1));

   if(Ask <= triggerPrice) return;

   // New SELL STOP is one SmartGrid1 above the last activated SELL.
   double newStop = NormalizePrice(
      lastPrice + PointsToPrice(SmartGrid1));

   double stopLevel = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;

   if(newStop >= Bid - stopLevel)
      return;

   double nextLot = NextRecoveryLot(lastLot);

   Print(EA_NAME,
         " SELL RULE 2 TRIGGERED. lastTicket=", lastTicket,
         " lastPrice=", DoubleToString(lastPrice, Digits),
         " lastLot=", DoubleToString(lastLot, DigitsLots),
         " trigger=", DoubleToString(triggerPrice, Digits),
         " Bid=", DoubleToString(Bid, Digits),
         " newSELLStop=", DoubleToString(newStop, Digits),
         " nextLot=", DoubleToString(nextLot, DigitsLots));

   // IMPORTANT: recovery pending is fixed at its business-rule level.
   // It is NOT trailing.
   SendPending(OP_SELLSTOP, newStop, nextLot,
               "EAGOLD SELL RECOVERY");
}

// ============================================================
// RULE 4 - SINGLE POSITION TAKE PROFIT + REENTRY
// ============================================================

bool CloseAllDirectionPending(int direction)
{
   int pendingType = (direction == OP_BUY ? OP_BUYSTOP : OP_SELLSTOP);
   bool allDeleted = true;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsEAGOLDOrder() || OrderType() != pendingType) continue;

      int ticket = OrderTicket();

      if(!DeletePendingOrder(ticket))
         allDeleted = false;
   }

   return(allDeleted);
}

void BuyCreateReentryAfterSingleTP()
{
   RefreshRates();

   double price = NormalizePrice(Ask + PointsToPrice(MiniGrid1));

   // No BUY position remains after the single-position TP close,
   // therefore Rule 3 resets the lot to the initial Lot.
   SendPending(OP_BUYSTOP, price, Lot,
               "EAGOLD BUY TP REENTRY");
}

void SellCreateReentryAfterSingleTP()
{
   RefreshRates();

   double price = NormalizePrice(Bid - PointsToPrice(MiniGrid1));

   // No SELL position remains after the single-position TP close,
   // therefore Rule 3 resets the lot to the initial Lot.
   SendPending(OP_SELLSTOP, price, Lot,
               "EAGOLD SELL TP REENTRY");
}

void BuySingleTakeProfit()
{
   if(TakeProfit <= 0.0) return;

   // Rule 5 owns any multi-position basket.
   if(CountDirectionPositions(OP_BUY) != 1) return;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsEAGOLDOrder() || OrderType() != OP_BUY) continue;

      double profit = OrderProfit();
      if(profit < TakeProfit) continue;

      int ticket = OrderTicket();

      if(CloseMarketOrder(ticket))
      {
         Print(EA_NAME,
               " BUY RULE 4: TakeProfit reached. ticket=", ticket,
               " profit=", DoubleToString(profit, 2),
               " target=", DoubleToString(TakeProfit, 2));

         // Rule 4: immediately create a new BUY STOP
         // at 1 x MiniGrid1 from current price.
         BuyCreateReentryAfterSingleTP();
      }

      break;
   }
}

void SellSingleTakeProfit()
{
   if(TakeProfit <= 0.0) return;

   // Rule 5 owns any multi-position basket.
   if(CountDirectionPositions(OP_SELL) != 1) return;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsEAGOLDOrder() || OrderType() != OP_SELL) continue;

      double profit = OrderProfit();
      if(profit < TakeProfit) continue;

      int ticket = OrderTicket();

      if(CloseMarketOrder(ticket))
      {
         Print(EA_NAME,
               " SELL RULE 4: TakeProfit reached. ticket=", ticket,
               " profit=", DoubleToString(profit, 2),
               " target=", DoubleToString(TakeProfit, 2));

         // Rule 4: immediately create a new SELL STOP
         // at 1 x MiniGrid1 from current price.
         SellCreateReentryAfterSingleTP();
      }

      break;
   }
}

// ============================================================
// RULE 5 - DIRECTIONAL BASKET CLOSE
// ============================================================

void BuyBasketClose()
{
   int count = CountDirectionPositions(OP_BUY);

   if(count <= 1) return;
   if(TakeProfit <= 0.0) return;

   double target = count * TakeProfit;
   double profit = DirectionBasketProfit(OP_BUY);

   if(profit < target) return;

   Print(EA_NAME,
         " BUY RULE 5: BASKET TARGET REACHED. count=", count,
         " basketProfit=", DoubleToString(profit, 2),
         " target=", DoubleToString(target, 2));

   // Close ALL BUY positions. Do not touch SELL.
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsEAGOLDOrder() || OrderType() != OP_BUY) continue;

      CloseMarketOrder(OrderTicket());
   }

   // Remove ALL BUY pending orders. Do not touch SELL.
   CloseAllDirectionPending(OP_BUY);
}

void SellBasketClose()
{
   int count = CountDirectionPositions(OP_SELL);

   if(count <= 1) return;
   if(TakeProfit <= 0.0) return;

   double target = count * TakeProfit;
   double profit = DirectionBasketProfit(OP_SELL);

   if(profit < target) return;

   Print(EA_NAME,
         " SELL RULE 5: BASKET TARGET REACHED. count=", count,
         " basketProfit=", DoubleToString(profit, 2),
         " target=", DoubleToString(target, 2));

   // Close ALL SELL positions. Do not touch BUY.
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsEAGOLDOrder() || OrderType() != OP_SELL) continue;

      CloseMarketOrder(OrderTicket());
   }

   // Remove ALL SELL pending orders. Do not touch BUY.
   CloseAllDirectionPending(OP_SELL);
}

// ============================================================
// INDEPENDENT MACHINES
// ============================================================

void BuyMachine()
{
   BuyBasketClose();
   BuySingleTakeProfit();
   BuyRecovery();
   BuyCreateFirstOrder();
}

void SellMachine()
{
   SellBasketClose();
   SellSingleTakeProfit();
   SellRecovery();
   SellCreateFirstOrder();
}

// ============================================================
// EA LIFECYCLE
// ============================================================

int OnInit()
{
   Print(EA_NAME,
         " v0.040 initialized.",
         " Rules R1-R5 active.",
         " MiniGrid1=", DoubleToString(MiniGrid1, 0),
         " SmartGrid1=", DoubleToString(SmartGrid1, 0),
         " Multiplier=", DoubleToString(Multiplier, 2),
         " Lot=", DoubleToString(Lot, DigitsLots),
         " MaxOpenLot=", DoubleToString(MaxOpenLot, DigitsLots),
         " TakeProfitMoney=", DoubleToString(TakeProfit, 2));

   // Rule 1 is the initial state only.
   BuyCreateFirstOrder();
   SellCreateFirstOrder();

   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
}

void OnTick()
{
   // BUY and SELL are fully independent.
   BuyMachine();
   SellMachine();
}
