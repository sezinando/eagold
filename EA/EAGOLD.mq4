#property strict
#property version   "0.020"
#property description "EAGOLD - SmartGrid activation and SELL multiplier progression"

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
input int    WaitSeconds              = 0;
input double FirstStep                = 160.0;
input double MiniGrid1                = 250.0;
input double SmartGrid1               = 80.0;
input double MiniGrid2                = 80.0;
input double SmartGrid2               = 60.0;
input double PendingStepTrail         = 50.0;
input int    MaxTrades                = 2000;
input bool   EnableCloseBy            = false;
input double BuyProgressionTolerance  = 10.0;

string EA_NAME = "EAGOLD";
int LastProcessedBuyCloseTicket = -1;

double PointsToPrice(double points){ return(points * Point); }
double NormalizePrice(double price){ return(NormalizeDouble(price, Digits)); }

double NormalizeLot(double lot)
{
   if(lot < Lot) lot = Lot;
   if(MaxOpenLot > 0.0 && lot > MaxOpenLot) lot = MaxOpenLot;
   return(NormalizeDouble(lot, DigitsLots));
}

// SELL progression uses Multiplier plus LotIncrement, exactly as specified:
// next SELL = previous SELL * Multiplier + LotIncrement, capped at MaxOpenLot.
double NextSellLot(double previousLot)
{
   double next = (previousLot * Multiplier) + LotIncrement;
   return(NormalizeLot(next));
}

// BUY progression remains fixed-increment and independent from SELL:
// next BUY = previous BUY + LotIncrement, capped at MaxOpenLot.
double NextBuyLot(double previousLot)
{
   double next = previousLot + LotIncrement;
   return(NormalizeLot(next));
}

bool IsEAGOLDOrder()
{
   return(OrderSymbol() == Symbol() && OrderMagicNumber() == MagicNumber);
}

int CountOrders(int type)
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

int SendPending(int type, double price, double lots, string comment)
{
   RefreshRates();
   double stopLevel = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;
   price = NormalizePrice(price);
   lots = NormalizeLot(lots);

   if(type == OP_BUYSTOP && price <= Ask + stopLevel) return(-1);
   if(type == OP_SELLSTOP && price >= Bid - stopLevel) return(-1);

   ResetLastError();
   int ticket = OrderSend(Symbol(), type, lots, price, 0, 0, 0,
                          comment, MagicNumber, 0, clrNONE);

   if(ticket < 0)
      Print(EA_NAME, " OrderSend failed. type=", type,
            " price=", DoubleToString(price, Digits),
            " lot=", DoubleToString(lots, DigitsLots),
            " error=", GetLastError());
   else
      Print(EA_NAME, " pending created. ticket=", ticket,
            " type=", type,
            " price=", DoubleToString(price, Digits),
            " lot=", DoubleToString(lots, DigitsLots));

   return(ticket);
}

void CreateFirstStepOrders()
{
   int total = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(IsEAGOLDOrder()) total++;
   }

   if(total > 0) return;

   RefreshRates();
   double buyPrice  = NormalizePrice(Ask + PointsToPrice(FirstStep));
   double sellPrice = NormalizePrice(Bid - PointsToPrice(FirstStep));

   SendPending(OP_BUYSTOP, buyPrice, NormalizeLot(Lot), "EAGOLD FIRST STEP BUY");
   SendPending(OP_SELLSTOP, sellPrice, NormalizeLot(Lot), "EAGOLD FIRST STEP SELL");
}

void TrailBuyStop()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsEAGOLDOrder() || OrderType() != OP_BUYSTOP) continue;

      RefreshRates();
      double desired   = NormalizePrice(Ask + PointsToPrice(FirstStep));
      double current   = OrderOpenPrice();
      double movement  = current - desired;
      double trailStep = PointsToPrice(PendingStepTrail);

      if(desired >= current) continue;
      if(movement < trailStep) continue;

      double stopLevel = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;
      if(desired <= Ask + stopLevel) continue;

      ResetLastError();
      if(!OrderModify(OrderTicket(), desired, 0, 0, 0, clrNONE))
         Print(EA_NAME, " BUY STOP modify failed. ticket=", OrderTicket(),
               " current=", DoubleToString(current, Digits),
               " desired=", DoubleToString(desired, Digits),
               " error=", GetLastError());
      else
         Print(EA_NAME, " BUY STOP TRAIL DOWN. ticket=", OrderTicket(),
               " from=", DoubleToString(current, Digits),
               " to=", DoubleToString(desired, Digits));
   }
}

void TrailSellStop()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsEAGOLDOrder() || OrderType() != OP_SELLSTOP) continue;

      string comment = OrderComment();
      if(comment != "EAGOLD FIRST STEP SELL" &&
         comment != "EAGOLD SELL PROGRESSION")
         continue;

      RefreshRates();
      double desired   = NormalizePrice(Bid - PointsToPrice(FirstStep));
      double current   = OrderOpenPrice();
      double movement  = desired - current;
      double trailStep = PointsToPrice(PendingStepTrail);

      if(desired <= current) continue;
      if(movement < trailStep) continue;

      double stopLevel = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;
      if(desired >= Bid - stopLevel) continue;

      ResetLastError();
      if(!OrderModify(OrderTicket(), desired, 0, 0, 0, clrNONE))
         Print(EA_NAME, " SELL STOP modify failed. ticket=", OrderTicket(),
               " comment=", comment,
               " current=", DoubleToString(current, Digits),
               " desired=", DoubleToString(desired, Digits),
               " error=", GetLastError());
      else
         Print(EA_NAME, " SELL STOP TRAIL UP. ticket=", OrderTicket(),
               " comment=", comment,
               " from=", DoubleToString(current, Digits),
               " to=", DoubleToString(desired, Digits));
   }
}

void ProcessBuyTakeProfit()
{
   if(TakeProfit <= 0.0) return;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsEAGOLDOrder() || OrderType() != OP_BUY) continue;
      if(OrderComment() != "EAGOLD FIRST STEP BUY") continue;

      RefreshRates();
      double profit = OrderProfit();
      if(profit < TakeProfit) continue;

      int ticket  = OrderTicket();
      double lots = OrderLots();
      double bid  = NormalizePrice(Bid);

      ResetLastError();
      if(!OrderClose(ticket, lots, bid, 0, clrNONE))
         Print(EA_NAME, " INITIAL BUY MONETARY TAKE PROFIT close failed. ticket=", ticket,
               " profit=", DoubleToString(profit, 2),
               " targetMoney=", DoubleToString(TakeProfit, 2),
               " error=", GetLastError());
      else
         Print(EA_NAME, " INITIAL BUY MONETARY TAKE PROFIT. ticket=", ticket,
               " profit=", DoubleToString(profit, 2),
               " targetMoney=", DoubleToString(TakeProfit, 2));
   }
}

void ProcessSellTakeProfit()
{
   if(TakeProfit <= 0.0) return;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsEAGOLDOrder() || OrderType() != OP_SELL) continue;
      if(OrderComment() != "EAGOLD FIRST STEP SELL") continue;

      RefreshRates();
      double profit = OrderProfit();
      if(profit < TakeProfit) continue;

      int ticket  = OrderTicket();
      double lots = OrderLots();
      double ask  = NormalizePrice(Ask);

      ResetLastError();
      if(!OrderClose(ticket, lots, ask, 0, clrNONE))
         Print(EA_NAME, " INITIAL SELL MONETARY TAKE PROFIT close failed. ticket=", ticket,
               " profit=", DoubleToString(profit, 2),
               " targetMoney=", DoubleToString(TakeProfit, 2),
               " error=", GetLastError());
      else
         Print(EA_NAME, " INITIAL SELL MONETARY TAKE PROFIT. ticket=", ticket,
               " profit=", DoubleToString(profit, 2),
               " targetMoney=", DoubleToString(TakeProfit, 2));
   }
}

bool GetLatestSell(double &latestSellOpen, double &latestSellLot, int &latestSellTicket)
{
   latestSellOpen   = 0.0;
   latestSellLot    = NormalizeLot(Lot);
   latestSellTicket = -1;
   datetime latestSellTime = 0;
   bool foundSell = false;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsEAGOLDOrder() || OrderType() != OP_SELL) continue;

      datetime openTime = OrderOpenTime();
      int ticket = OrderTicket();

      if(!foundSell ||
         openTime > latestSellTime ||
         (openTime == latestSellTime && ticket > latestSellTicket))
      {
         foundSell = true;
         latestSellTime = openTime;
         latestSellOpen = OrderOpenPrice();
         latestSellLot = OrderLots();
         latestSellTicket = ticket;
      }
   }

   return(foundSell);
}

// SELL: the next SELL STOP cannot be activated before price moves
// 2 x SmartGrid1 against the latest activated SELL.
// The SmartGrid reference is ALWAYS the latest activated SELL.
// Lot = previous SELL lot * Multiplier + LotIncrement, capped.
void ProcessSellProgression()
{
   if(SmartGrid1 <= 0.0) return;
   if(CountOrders(OP_SELLSTOP) > 0) return;

   double latestSellOpen = 0.0;
   double latestSellLot = NormalizeLot(Lot);
   int latestSellTicket = -1;

   if(!GetLatestSell(latestSellOpen, latestSellLot, latestSellTicket)) return;

   RefreshRates();

   double triggerDistance = PointsToPrice(2.0 * SmartGrid1);
   double triggerPrice = NormalizePrice(latestSellOpen + triggerDistance);

   if(Bid < triggerPrice) return;

   double newSellStop = triggerPrice;
   double stopLevel = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;
   if(newSellStop >= Bid - stopLevel) return;

   double nextSellLot = NextSellLot(latestSellLot);

   Print(EA_NAME,
         " SELL PROGRESSION TRIGGERED. latestTicket=", latestSellTicket,
         " latestSell=", DoubleToString(latestSellOpen, Digits),
         " latestLot=", DoubleToString(latestSellLot, DigitsLots),
         " nextLot=", DoubleToString(nextSellLot, DigitsLots),
         " Bid=", DoubleToString(Bid, Digits),
         " 2xSmartGrid=", DoubleToString(2.0 * SmartGrid1, 0),
         " trigger=", DoubleToString(triggerPrice, Digits));

   SendPending(OP_SELLSTOP, newSellStop, nextSellLot, "EAGOLD SELL PROGRESSION");
}

bool GetLatestBuy(double &latestBuyOpen, double &latestBuyLot, int &latestBuyTicket)
{
   latestBuyOpen   = 0.0;
   latestBuyLot    = NormalizeLot(Lot);
   latestBuyTicket = -1;
   datetime latestBuyTime = 0;
   bool foundBuy = false;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsEAGOLDOrder() || OrderType() != OP_BUY) continue;

      datetime openTime = OrderOpenTime();
      int ticket = OrderTicket();

      if(!foundBuy ||
         openTime > latestBuyTime ||
         (openTime == latestBuyTime && ticket > latestBuyTicket))
      {
         foundBuy = true;
         latestBuyTime = openTime;
         latestBuyOpen = OrderOpenPrice();
         latestBuyLot = OrderLots();
         latestBuyTicket = ticket;
      }
   }

   return(foundBuy);
}

// Last BUY closure marker is retained only to prevent duplicate processing.
void InitializeBuyCloseTracker()
{
   datetime latestCloseTime = 0;
   int latestTicket = -1;

   for(int i = OrdersHistoryTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
      if(!IsEAGOLDOrder() || OrderType() != OP_BUY) continue;

      datetime closeTime = OrderCloseTime();
      int ticket = OrderTicket();
      if(closeTime > latestCloseTime ||
         (closeTime == latestCloseTime && ticket > latestTicket))
      {
         latestCloseTime = closeTime;
         latestTicket = ticket;
      }
   }

   LastProcessedBuyCloseTicket = latestTicket;
}

// BUY: the next BUY STOP cannot be activated before price moves
// 2 x SmartGrid1 against the latest activated BUY.
// For BUY, adverse movement is downward. The pending BUY STOP is therefore
// placed at LastBuy - 2 x SmartGrid1, once price has reached that level.
// BUY lot progression is independent: previous BUY lot + LotIncrement.
void ProcessBuyProgression()
{
   if(SmartGrid1 <= 0.0) return;
   if(CountOrders(OP_BUYSTOP) > 0) return;

   double latestBuyOpen = 0.0;
   double latestBuyLot = NormalizeLot(Lot);
   int latestBuyTicket = -1;

   if(!GetLatestBuy(latestBuyOpen, latestBuyLot, latestBuyTicket)) return;

   RefreshRates();

   double triggerDistance = PointsToPrice(2.0 * SmartGrid1);
   double triggerPrice = NormalizePrice(latestBuyOpen - triggerDistance);

   // Price must have fallen 2 x SmartGrid1 against the latest BUY.
   if(Ask > triggerPrice) return;

   // A BUY STOP must be above the current ASK. If price has moved beyond
   // the trigger, place it at the trigger only when broker rules allow it.
   double newBuyStop = triggerPrice;
   double stopLevel = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;
   if(newBuyStop <= Ask + stopLevel) return;

   double nextBuyLot = NextBuyLot(latestBuyLot);

   Print(EA_NAME,
         " BUY PROGRESSION TRIGGERED. latestTicket=", latestBuyTicket,
         " latestBuy=", DoubleToString(latestBuyOpen, Digits),
         " latestLot=", DoubleToString(latestBuyLot, DigitsLots),
         " nextLot=", DoubleToString(nextBuyLot, DigitsLots),
         " Ask=", DoubleToString(Ask, Digits),
         " 2xSmartGrid=", DoubleToString(2.0 * SmartGrid1, 0),
         " trigger=", DoubleToString(triggerPrice, Digits));

   SendPending(OP_BUYSTOP, newBuyStop, nextBuyLot, "EAGOLD BUY PROGRESSION");
}

int OnInit()
{
   Print(EA_NAME, " v0.020 initialized. FirstStep=", DoubleToString(FirstStep, 0),
         " PendingStepTrail=", DoubleToString(PendingStepTrail, 0),
         " TakeProfitMoney=", DoubleToString(TakeProfit, 2),
         " SmartGrid1=", DoubleToString(SmartGrid1, 0),
         " 2xSmartGrid=", DoubleToString(2.0 * SmartGrid1, 0),
         " Multiplier=", DoubleToString(Multiplier, 2),
         " LotIncrement=", DoubleToString(LotIncrement, 2),
         " MiniGrid1=", DoubleToString(MiniGrid1, 0),
         " Lot=", DoubleToString(Lot, DigitsLots));

   InitializeBuyCloseTracker();
   CreateFirstStepOrders();
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
}

void OnTick()
{
   TrailSellStop();
   TrailBuyStop();
   ProcessBuyTakeProfit();
   ProcessSellTakeProfit();
   ProcessSellProgression();
   ProcessBuyProgression();
}
