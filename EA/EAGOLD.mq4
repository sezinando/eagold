//+------------------------------------------------------------------+
//|                                                   EAGOLD.mq4     |
//|              EAGOLD - ZEUS event-driven cycle model             |
//+------------------------------------------------------------------+
#property strict
#property version   "000.800"
#property description "EAGOLD - ZEUS event-driven bilateral grid, individual TP, basket profit/loss, adaptive spacing, lot ladder, averages and exposure."

//====================================================================
// SET / PARAMETROS OBSERVADOS NO ZEUS
//====================================================================
input int    MagicNumber          = 1001;
input double Lot                  = 0.01;
input double Multiplier           = 1.20;
input int    DigitsLots           = 2;
input double LotIncrement         = 0.01;
input double MaxOpenLot           = 3.00;
input double TakeProfit           = 5.00;   // distancia de preco para TP individual
input double BasketProfit         = 4.00;   // moeda da conta
input double BasketLoss           = 100.00; // moeda da conta
input int    SpreadLimit          = 100;    // pontos
input int    WaitSeconds          = 0;
input int    FirstStep            = 160;    // pontos
input int    MiniGrid1            = 340;    // pontos
input int    MiniGrid2            = 80;     // pontos
input int    PendingStepTrail     = 50;     // pontos
input int    SmartGrid1           = 80;     // pontos
input int    SmartGrid2           = 90;     // pontos
input int    MaxTrades            = 2000;

// O video mostrou uma escada discreta, e nao uma multiplicacao direta.
input bool   UseObservedLotLadder = true;
input bool   UseSmartGrid         = true;
input bool   UsePendingTrail      = true;
input bool   StartWithHedge       = true;

//====================================================================
// OBJETOS / ESTADO
//====================================================================
color AvgBuyColor  = clrBlue;
color AvgSellColor = clrRed;
color PanelColor   = clrWhite;
color LevelColor   = clrLime;

string AvgBuyLineName  = "EAGOLD_AVG_BUY_LINE";
string AvgSellLineName = "EAGOLD_AVG_SELL_LINE";
string AvgBuyTextName  = "EAGOLD_AVG_BUY_TEXT";
string AvgSellTextName = "EAGOLD_AVG_SELL_TEXT";
string PanelName       = "EAGOLD_EXPOSURE_PANEL";

int      BuySequence       = 0;
int      SellSequence      = 0;
int      CycleNumber       = 0;
datetime LastTradeTime     = 0;
datetime LastCycleStart    = 0;
int      LastBuyTicket     = -1;
int      LastSellTicket    = -1;

//====================================================================
// UTILITARIOS
//====================================================================

bool IsEAGOLDOrder()
{
   return(OrderSymbol() == Symbol() && OrderMagicNumber() == MagicNumber);
}

bool IsOpenPosition()
{
   return(OrderType() == OP_BUY || OrderType() == OP_SELL);
}

bool IsPendingOrder()
{
   int type = OrderType();
   return(type == OP_BUYLIMIT || type == OP_BUYSTOP ||
          type == OP_SELLLIMIT || type == OP_SELLSTOP);
}

double PointsToPrice(int points)
{
   return(points * Point);
}

double NormalizePrice(double price)
{
   return(NormalizeDouble(price, Digits));
}

double NormalizeLot(double lots)
{
   double minLot = MarketInfo(Symbol(), MODE_MINLOT);
   double maxLot = MarketInfo(Symbol(), MODE_MAXLOT);
   double step   = MarketInfo(Symbol(), MODE_LOTSTEP);

   if(step <= 0.0) step = LotIncrement;
   if(step <= 0.0) step = 0.01;

   if(lots < minLot) lots = minLot;
   if(maxLot > 0.0 && lots > maxLot) lots = maxLot;
   if(MaxOpenLot > 0.0 && lots > MaxOpenLot) lots = MaxOpenLot;

   lots = MathRound(lots / step) * step;

   if(lots < minLot) lots = minLot;
   if(maxLot > 0.0 && lots > maxLot) lots = maxLot;
   if(MaxOpenLot > 0.0 && lots > MaxOpenLot) lots = MaxOpenLot;

   return(NormalizeDouble(lots, DigitsLots));
}

// Escada observada no ciclo analisado.
double ObservedLotByIndex(int index)
{
   switch(index)
   {
      case 1:  return(0.01);
      case 2:  return(0.03);
      case 3:  return(0.05);
      case 4:  return(0.08);
      case 5:  return(0.10);
      case 6:  return(0.12);
      case 7:  return(0.15);
      case 8:  return(0.18);
      case 9:  return(0.20);
      case 10: return(0.23);
      case 11: return(0.26);
   }
   return(0.0);
}

double NextLotForSide(int side)
{
   int index = (side == OP_BUY ? BuySequence + 1 : SellSequence + 1);
   double nextLot = 0.0;

   if(UseObservedLotLadder)
      nextLot = ObservedLotByIndex(index);

   if(nextLot <= 0.0)
   {
      double base = ObservedLotByIndex(11);
      if(base <= 0.0) base = Lot;

      int extra = index - 11;
      if(extra < 1) extra = 1;

      nextLot = base;
      for(int i = 0; i < extra; i++)
         nextLot *= (Multiplier > 0.0 ? Multiplier : 1.0);
   }

   return(NormalizeLot(nextLot));
}

int CountOpenPositions()
{
   int count = 0;
   for(int i = OrdersTotal()-1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(IsEAGOLDOrder() && IsOpenPosition()) count++;
   }
   return(count);
}

int CountPendingOrders()
{
   int count = 0;
   for(int i = OrdersTotal()-1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(IsEAGOLDOrder() && IsPendingOrder()) count++;
   }
   return(count);
}

int CountSidePositions(int side)
{
   int count = 0;
   for(int i = OrdersTotal()-1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(IsEAGOLDOrder() && OrderType() == side) count++;
   }
   return(count);
}

bool SpreadOK()
{
   if(SpreadLimit <= 0) return(true);
   RefreshRates();
   return(((Ask - Bid) / Point) <= SpreadLimit);
}

bool WaitOK()
{
   if(WaitSeconds <= 0 || LastTradeTime <= 0) return(true);
   return((TimeCurrent() - LastTradeTime) >= WaitSeconds);
}

bool TradeCapacityOK()
{
   if(MaxTrades <= 0) return(true);
   return(CountOpenPositions() + CountPendingOrders() < MaxTrades);
}

//====================================================================
// PRECO MEDIO / EXPOSICAO
//====================================================================

bool GetSideAverage(int side, double &averagePrice, double &totalLots)
{
   double weighted = 0.0;
   totalLots = 0.0;

   for(int i = OrdersTotal()-1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsEAGOLDOrder() || OrderType() != side) continue;

      weighted += OrderOpenPrice() * OrderLots();
      totalLots += OrderLots();
   }

   if(totalLots <= 0.0)
   {
      averagePrice = 0.0;
      return(false);
   }

   averagePrice = NormalizePrice(weighted / totalLots);
   return(true);
}

void GetSideExposure(int side, double &lots, double &pnl, int &count)
{
   lots = 0.0;
   pnl = 0.0;
   count = 0;

   for(int i = OrdersTotal()-1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsEAGOLDOrder() || OrderType() != side) continue;

      lots += OrderLots();
      pnl += OrderProfit() + OrderSwap() + OrderCommission();
      count++;
   }
}

double CurrentBasketProfit()
{
   double total = 0.0;
   for(int i = OrdersTotal()-1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsEAGOLDOrder() || !IsOpenPosition()) continue;
      total += OrderProfit() + OrderSwap() + OrderCommission();
   }
   return(total);
}

//====================================================================
// DISPLAY
//====================================================================

void DeleteObjectIfExists(string name)
{
   if(ObjectFind(0, name) >= 0)
      ObjectDelete(0, name);
}

void DrawAverageLine(string lineName, string textName, double averagePrice,
                     color lineColor, string sideText)
{
   if(ObjectFind(0, lineName) < 0)
      ObjectCreate(0, lineName, OBJ_HLINE, 0, 0, averagePrice);

   ObjectSetDouble(0, lineName, OBJPROP_PRICE1, averagePrice);
   ObjectSetInteger(0, lineName, OBJPROP_COLOR, lineColor);
   ObjectSetInteger(0, lineName, OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, lineName, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, lineName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, lineName, OBJPROP_SELECTED, false);

   datetime t = (Bars > 0 ? Time[0] : TimeCurrent());
   if(ObjectFind(0, textName) < 0)
      ObjectCreate(0, textName, OBJ_TEXT, 0, t, averagePrice);

   ObjectMove(0, textName, 0, t, averagePrice);
   ObjectSetString(0, textName, OBJPROP_TEXT,
                   sideText + " " + DoubleToString(averagePrice, Digits));
   ObjectSetString(0, textName, OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, textName, OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(0, textName, OBJPROP_COLOR, lineColor);
   ObjectSetInteger(0, textName, OBJPROP_ANCHOR, ANCHOR_LEFT);
   ObjectSetInteger(0, textName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, textName, OBJPROP_SELECTED, false);
}

void UpdateAveragePriceDisplay()
{
   double buyAvg, buyLots, sellAvg, sellLots;
   bool hasBuy  = GetSideAverage(OP_BUY, buyAvg, buyLots);
   bool hasSell = GetSideAverage(OP_SELL, sellAvg, sellLots);

   if(hasBuy)
      DrawAverageLine(AvgBuyLineName, AvgBuyTextName, buyAvg, AvgBuyColor, "BUY AVG");
   else
   {
      DeleteObjectIfExists(AvgBuyLineName);
      DeleteObjectIfExists(AvgBuyTextName);
   }

   if(hasSell)
      DrawAverageLine(AvgSellLineName, AvgSellTextName, sellAvg, AvgSellColor, "SELL AVG");
   else
   {
      DeleteObjectIfExists(AvgSellLineName);
      DeleteObjectIfExists(AvgSellTextName);
   }
}

void DeleteAveragePriceDisplay()
{
   DeleteObjectIfExists(AvgBuyLineName);
   DeleteObjectIfExists(AvgSellLineName);
   DeleteObjectIfExists(AvgBuyTextName);
   DeleteObjectIfExists(AvgSellTextName);
}

void CreateOrUpdatePanel()
{
   if(ObjectFind(0, PanelName) < 0)
      ObjectCreate(0, PanelName, OBJ_LABEL, 0, 0, 0);

   double buyLots, buyPnl, sellLots, sellPnl;
   int buyCount, sellCount;
   GetSideExposure(OP_BUY, buyLots, buyPnl, buyCount);
   GetSideExposure(OP_SELL, sellLots, sellPnl, sellCount);

   double totalLots = buyLots + sellLots;
   double totalPnl = buyPnl + sellPnl;

   string text =
      "EAGOLD v0.800 [ZEUS EVENT MODEL]\n" +
      "----------------------------------------------\n" +
      "CYCLE: " + IntegerToString(CycleNumber) +
      "   OPEN: " + IntegerToString(buyCount + sellCount) +
      "   PEND: " + IntegerToString(CountPendingOrders()) + "\n" +
      "BUY   " + IntegerToString(buyCount) + " ord  " +
      DoubleToString(buyLots, 2) + " lot   P/L " + DoubleToString(buyPnl, 2) + "\n" +
      "SELL  " + IntegerToString(sellCount) + " ord  " +
      DoubleToString(sellLots, 2) + " lot   P/L " + DoubleToString(sellPnl, 2) + "\n" +
      "----------------------------------------------\n" +
      "TOTAL " + IntegerToString(buyCount + sellCount) + " ord  " +
      DoubleToString(totalLots, 2) + " lot   P/L " + DoubleToString(totalPnl, 2) + "\n" +
      "Balance: " + DoubleToString(AccountBalance(), 2) +
      "   Equity: " + DoubleToString(AccountEquity(), 2) + "\n" +
      "TP: " + DoubleToString(TakeProfit, 2) +
      "  Basket+: " + DoubleToString(BasketProfit, 2) +
      "  Basket-: " + DoubleToString(BasketLoss, 2);

   ObjectSetString(0, PanelName, OBJPROP_TEXT, text);
   ObjectSetString(0, PanelName, OBJPROP_FONT, "Consolas");
   ObjectSetInteger(0, PanelName, OBJPROP_FONTSIZE, 9);
   ObjectSetInteger(0, PanelName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, PanelName, OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0, PanelName, OBJPROP_YDISTANCE, 20);
   ObjectSetInteger(0, PanelName, OBJPROP_COLOR, PanelColor);
   ObjectSetInteger(0, PanelName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, PanelName, OBJPROP_SELECTED, false);
}

//====================================================================
// LOTES / ESTADO A PARTIR DAS ORDENS EXISTENTES
//====================================================================

void RebuildSequencesFromOpenOrders()
{
   BuySequence = 0;
   SellSequence = 0;

   for(int i = OrdersTotal()-1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsEAGOLDOrder() || !IsOpenPosition()) continue;

      if(OrderType() == OP_BUY)  BuySequence++;
      if(OrderType() == OP_SELL) SellSequence++;
   }
}

//====================================================================
// ENVIO DE ORDENS
//====================================================================

bool SendMarket(int side, double lots, string comment)
{
   if(!SpreadOK() || !WaitOK() || !TradeCapacityOK()) return(false);

   RefreshRates();
   lots = NormalizeLot(lots);
   if(lots <= 0.0) return(false);

   double price = (side == OP_BUY ? Ask : Bid);
   price = NormalizePrice(price);

   ResetLastError();
   int ticket = OrderSend(Symbol(), side, lots, price, 10, 0, 0,
                          comment, MagicNumber, 0, clrNONE);
   if(ticket < 0)
   {
      Print("EAGOLD ERROR - Market order failed. Side=", side,
            " Lots=", DoubleToString(lots, DigitsLots),
            " Error=", GetLastError());
      return(false);
   }

   LastTradeTime = TimeCurrent();
   if(side == OP_BUY)
   {
      BuySequence++;
      LastBuyTicket = ticket;
   }
   else
   {
      SellSequence++;
      LastSellTicket = ticket;
   }

   Print("EAGOLD EVENT ENTRY - ", comment, " Ticket=", ticket,
         " Lots=", DoubleToString(lots, DigitsLots),
         " Price=", DoubleToString(price, Digits));

   return(true);
}

bool SendPending(int type, double lots, double price, string comment)
{
   if(!SpreadOK() || !TradeCapacityOK()) return(false);

   RefreshRates();
   lots = NormalizeLot(lots);
   price = NormalizePrice(price);

   double minDistance = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;

   if(type == OP_BUYSTOP && price <= Ask + minDistance) return(false);
   if(type == OP_SELLSTOP && price >= Bid - minDistance) return(false);
   if(type == OP_BUYLIMIT && price >= Ask - minDistance) return(false);
   if(type == OP_SELLLIMIT && price <= Bid + minDistance) return(false);

   ResetLastError();
   int ticket = OrderSend(Symbol(), type, lots, price, 10, 0, 0,
                          comment, MagicNumber, 0, clrNONE);
   if(ticket < 0)
   {
      Print("EAGOLD ERROR - Pending failed. Type=", type,
            " Lots=", DoubleToString(lots, DigitsLots),
            " Price=", DoubleToString(price, Digits),
            " Error=", GetLastError());
      return(false);
   }

   LastTradeTime = TimeCurrent();
   Print("EAGOLD EVENT PENDING - Ticket=", ticket,
         " Type=", type,
         " Lots=", DoubleToString(lots, DigitsLots),
         " Price=", DoubleToString(price, Digits));
   return(true);
}

//====================================================================
// SEMENTE DO CICLO
//====================================================================

bool HasAnyEAGOLDOrder()
{
   return(CountOpenPositions() > 0 || CountPendingOrders() > 0);
}

bool StartNewCycle()
{
   if(HasAnyEAGOLDOrder()) return(false);
   if(!SpreadOK() || !WaitOK()) return(false);

   BuySequence = 0;
   SellSequence = 0;
   CycleNumber++;
   LastCycleStart = TimeCurrent();

   bool okBuy = SendMarket(OP_BUY, Lot, "EAGOLD CYCLE BUY #1");
   bool okSell = false;

   if(StartWithHedge)
      okSell = SendMarket(OP_SELL, Lot, "EAGOLD CYCLE SELL #1");
   else
      okSell = true;

   if(!okBuy || !okSell)
   {
      Print("EAGOLD WARNING - Seed cycle incomplete. BUY=", okBuy,
            " SELL=", okSell);
   }

   CreateOrUpdatePanel();
   UpdateAveragePriceDisplay();
   return(okBuy || okSell);
}

//====================================================================
// TP INDIVIDUAL
//====================================================================

bool PositionReachedTakeProfit()
{
   if(TakeProfit <= 0.0) return(false);

   if(OrderType() == OP_BUY)
      return((Bid - OrderOpenPrice()) >= TakeProfit);

   if(OrderType() == OP_SELL)
      return((OrderOpenPrice() - Ask) >= TakeProfit);

   return(false);
}

void ProcessIndividualTakeProfits()
{
   if(TakeProfit <= 0.0) return;

   RefreshRates();

   for(int i = OrdersTotal()-1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsEAGOLDOrder() || !IsOpenPosition()) continue;
      if(!PositionReachedTakeProfit()) continue;

      int ticket = OrderTicket();
      int side = OrderType();
      double lots = OrderLots();
      double closePrice = (side == OP_BUY ? Bid : Ask);
      double pnl = OrderProfit() + OrderSwap() + OrderCommission();

      ResetLastError();
      if(OrderClose(ticket, lots, closePrice, 10, clrNONE))
      {
         Print("EAGOLD EVENT TP - Ticket=", ticket,
               " Side=", side == OP_BUY ? "BUY" : "SELL",
               " Lots=", DoubleToString(lots, DigitsLots),
               " P/L=", DoubleToString(pnl, 2));
      }
      else
      {
         Print("EAGOLD ERROR - TP close failed. Ticket=", ticket,
               " Error=", GetLastError());
      }
   }
}

//====================================================================
// BASKET PROFIT / LOSS
//====================================================================

bool CloseAllEAGOLD()
{
   bool anyAction = false;
   RefreshRates();

   for(int i = OrdersTotal()-1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsEAGOLDOrder() || !IsOpenPosition()) continue;

      int ticket = OrderTicket();
      int side = OrderType();
      double lots = OrderLots();
      double price = (side == OP_BUY ? Bid : Ask);

      ResetLastError();
      if(OrderClose(ticket, lots, price, 10, clrNONE))
         anyAction = true;
      else
         Print("EAGOLD ERROR - Basket close failed. Ticket=", ticket,
               " Error=", GetLastError());
   }

   for(int j = OrdersTotal()-1; j >= 0; j--)
   {
      if(!OrderSelect(j, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsEAGOLDOrder() || !IsPendingOrder()) continue;

      int pendingTicket = OrderTicket();
      ResetLastError();
      if(OrderDelete(pendingTicket))
         anyAction = true;
      else
         Print("EAGOLD ERROR - Pending delete failed. Ticket=", pendingTicket,
               " Error=", GetLastError());
   }

   return(anyAction);
}

bool CheckBasketExit()
{
   double basket = CurrentBasketProfit();

   if(BasketProfit > 0.0 && basket >= BasketProfit)
   {
      Print("EAGOLD EVENT BASKET PROFIT - Current=", DoubleToString(basket,2),
            " Target=", DoubleToString(BasketProfit,2));
      CloseAllEAGOLD();
      BuySequence = 0;
      SellSequence = 0;
      LastTradeTime = TimeCurrent();
      return(true);
   }

   if(BasketLoss > 0.0 && basket <= -BasketLoss)
   {
      Print("EAGOLD EVENT BASKET LOSS - Current=", DoubleToString(basket,2),
            " Limit=", DoubleToString(BasketLoss,2));
      CloseAllEAGOLD();
      BuySequence = 0;
      SellSequence = 0;
      LastTradeTime = TimeCurrent();
      return(true);
   }

   return(false);
}

//====================================================================
// DISTANCIA / GRID
//====================================================================

double LastOpenPrice(int side)
{
   datetime latest = 0;
   double price = 0.0;

   for(int i = OrdersTotal()-1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsEAGOLDOrder() || OrderType() != side) continue;

      if(OrderOpenTime() >= latest)
      {
         latest = OrderOpenTime();
         price = OrderOpenPrice();
      }
   }

   return(price);
}

// A distancia e hierarquica: apos a primeira expansao usa MiniGrid1;
// em niveis subsequentes pode usar SmartGrid1/2 e MiniGrid2.
int GridDistanceForSide(int side)
{
   int sequence = (side == OP_BUY ? BuySequence : SellSequence);

   if(sequence <= 1)
      return(FirstStep);

   if(UseSmartGrid)
   {
      if(sequence % 2 == 0 && SmartGrid1 > 0)
         return(SmartGrid1);
      if(sequence % 2 == 1 && SmartGrid2 > 0)
         return(SmartGrid2);
   }

   if(MiniGrid2 > 0 && sequence >= 4)
      return(MiniGrid2);

   if(MiniGrid1 > 0)
      return(MiniGrid1);

   return(FirstStep);
}

//====================================================================
// GRID BILATERAL
//====================================================================

bool SideNeedsExpansion(int side)
{
   double avg, lots;
   if(!GetSideAverage(side, avg, lots)) return(false);

   double last = LastOpenPrice(side);
   if(last <= 0.0) return(false);

   RefreshRates();

   // BUY cresce quando o preco anda para baixo contra a perna BUY.
   if(side == OP_BUY)
   {
      double distance = last - Bid;
      return(distance >= PointsToPrice(GridDistanceForSide(side)));
   }

   // SELL cresce quando o preco anda para cima contra a perna SELL.
   if(side == OP_SELL)
   {
      double distance = Ask - last;
      return(distance >= PointsToPrice(GridDistanceForSide(side)));
   }

   return(false);
}

void ProcessSideExpansion(int side)
{
   if(!SideNeedsExpansion(side)) return;
   if(!SpreadOK() || !WaitOK() || !TradeCapacityOK()) return;

   double lots = NextLotForSide(side);
   if(lots <= 0.0) return;

   string comment = (side == OP_BUY ? "EAGOLD GRID BUY" : "EAGOLD GRID SELL");
   SendMarket(side, lots, comment);
}

//====================================================================
// PENDENTES / TRAILING
//====================================================================

bool HasPendingSide(int pendingType)
{
   for(int i = OrdersTotal()-1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(IsEAGOLDOrder() && OrderType() == pendingType)
         return(true);
   }
   return(false);
}

void EnsureOppositePending()
{
   if(!StartWithHedge) return;

   double buyAvg, buyLots, sellAvg, sellLots;
   bool hasBuy = GetSideAverage(OP_BUY, buyAvg, buyLots);
   bool hasSell = GetSideAverage(OP_SELL, sellAvg, sellLots);

   RefreshRates();

   // Se existe BUY e nao existe SELL, mantem um SELL STOP abaixo.
   if(hasBuy && !hasSell && !HasPendingSide(OP_SELLSTOP))
   {
      double price = NormalizePrice(buyAvg - PointsToPrice(FirstStep));
      SendPending(OP_SELLSTOP, NextLotForSide(OP_SELL), price, "EAGOLD SELL STOP");
   }

   // Se existe SELL e nao existe BUY, mantem um BUY STOP acima.
   if(hasSell && !hasBuy && !HasPendingSide(OP_BUYSTOP))
   {
      double price = NormalizePrice(sellAvg + PointsToPrice(FirstStep));
      SendPending(OP_BUYSTOP, NextLotForSide(OP_BUY), price, "EAGOLD BUY STOP");
   }
}

void TrailPendingOrders()
{
   if(!UsePendingTrail || PendingStepTrail <= 0) return;

   RefreshRates();
   double distance = PointsToPrice(PendingStepTrail);
   double minDistance = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;

   for(int i = OrdersTotal()-1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsEAGOLDOrder()) continue;

      int type = OrderType();
      if(type != OP_SELLSTOP && type != OP_BUYSTOP) continue;

      double desired = OrderOpenPrice();

      if(type == OP_SELLSTOP)
      {
         desired = NormalizePrice(Bid - distance);
         if(desired > Bid - minDistance)
            desired = NormalizePrice(Bid - minDistance);

         // SELL STOP acompanha somente para cima.
         if(desired <= OrderOpenPrice() + Point/2.0) continue;
      }
      else
      {
         desired = NormalizePrice(Ask + distance);
         if(desired < Ask + minDistance)
            desired = NormalizePrice(Ask + minDistance);

         // BUY STOP acompanha somente para baixo.
         if(desired >= OrderOpenPrice() - Point/2.0) continue;
      }

      int ticket = OrderTicket();
      double oldPrice = OrderOpenPrice();
      ResetLastError();
      if(OrderModify(ticket, desired, 0, 0, 0, clrNONE))
      {
         Print("EAGOLD EVENT TRAIL - Ticket=", ticket,
               " Old=", DoubleToString(oldPrice, Digits),
               " New=", DoubleToString(desired, Digits));
      }
      else
      {
         Print("EAGOLD ERROR - Pending trail failed. Ticket=", ticket,
               " Error=", GetLastError());
      }
   }
}

//====================================================================
// CONTROLE DO CICLO
//====================================================================

void ProcessCycle()
{
   // 1. Saida individual primeiro.
   ProcessIndividualTakeProfits();

   // 2. Basket e a saida global.
   if(CheckBasketExit())
      return;

   // 3. Reconstrucao das sequencias depois de TP.
   RebuildSequencesFromOpenOrders();

   // 4. Mantem a contraparte pendente quando uma perna ficou vazia.
   EnsureOppositePending();

   // 5. Trailing das pendentes.
   TrailPendingOrders();

   // 6. Expansao bilateral por movimento adverso.
   ProcessSideExpansion(OP_BUY);
   ProcessSideExpansion(OP_SELL);
}

//====================================================================
// EVENTOS MT4
//====================================================================

int OnInit()
{
   RebuildSequencesFromOpenOrders();

   if(HasAnyEAGOLDOrder())
   {
      CycleNumber = 1;
      Print("EAGOLD - Existing cycle recovered. BUYseq=", BuySequence,
            " SELLseq=", SellSequence);
   }
   else
   {
      CycleNumber = 0;
   }

   CreateOrUpdatePanel();
   UpdateAveragePriceDisplay();
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   DeleteAveragePriceDisplay();
   DeleteObjectIfExists(PanelName);
}

void OnTick()
{
   if(!HasAnyEAGOLDOrder())
      StartNewCycle();
   else
      ProcessCycle();

   UpdateAveragePriceDisplay();
   CreateOrUpdatePanel();
   ChartRedraw(0);
}
//+------------------------------------------------------------------+
