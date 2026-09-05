//+------------------------------------------------------------------+
//|                                                   EAGOLD.mq4     |
//|        EAGOLD - ZEUS interpretation / first-cycle model         |
//+------------------------------------------------------------------+
#property strict
#property version   "000.700"
#property description "EAGOLD - ZEUS interpretation: two legs, individual TP, basket, adaptive grid, lot ladder, averages and exposure."

//====================================================================
// CONFIGURACAO BASE / SET ZEUS OBSERVADO
//====================================================================
input int    MagicNumber        = 1001;
input double Lot                = 0.01;
input double Multiplier         = 1.20;
input int    DigitsLots         = 2;
input double LotIncrement       = 0.01;
input double MaxOpenLot         = 3.00;
input double TakeProfit         = 5.00;
input double BasketProfit       = 4.00;
input int    SpreadLimit        = 100;
input int    WaitSeconds        = 0;
input int    FirstStep          = 160;
input int    MiniGrid1          = 340;
input int    MiniGrid2          = 80;
input int    PendingStepTrail   = 50;
input int    SmartGrid1        = 80;
input int    SmartGrid2        = 90;
input int    MaxTrades          = 2000;

// Modelo reverso do ciclo observado no ZEUS.
// A sequencia observada nao e uma multiplicacao simples 1.20.
// Por isso usamos uma escada discreta e, apos ela, o multiplier como fallback.
input bool   UseObservedLotLadder = true;

color AvgBuyColor  = clrBlue;
color AvgSellColor = clrRed;
color PanelColor   = clrWhite;

string Prefix            = "EAGOLD_";
string AvgBuyLineName   = "EAGOLD_AVG_BUY_LINE";
string AvgSellLineName  = "EAGOLD_AVG_SELL_LINE";
string AvgBuyTextName   = "EAGOLD_AVG_BUY_TEXT";
string AvgSellTextName  = "EAGOLD_AVG_SELL_TEXT";
string PanelName        = "EAGOLD_EXPOSURE_PANEL";

int    BuySequence  = 0;
int    SellSequence = 0;
datetime LastTradeTime = 0;

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

double NormalizeLot(double lots)
{
   double minLot  = MarketInfo(Symbol(), MODE_MINLOT);
   double maxLot  = MarketInfo(Symbol(), MODE_MAXLOT);
   double step    = MarketInfo(Symbol(), MODE_LOTSTEP);

   if(step <= 0.0) step = LotIncrement;
   if(step <= 0.0) step = 0.01;

   if(lots < minLot) lots = minLot;
   if(lots > maxLot) lots = maxLot;
   if(MaxOpenLot > 0.0 && lots > MaxOpenLot) lots = MaxOpenLot;

   lots = MathRound(lots / step) * step;
   if(lots < minLot) lots = minLot;
   if(MaxOpenLot > 0.0 && lots > MaxOpenLot) lots = MaxOpenLot;

   return(NormalizeDouble(lots, DigitsLots));
}

// Escada observada no video: 0.01, 0.03, 0.05, 0.08...
// O indice e por ordem aberta daquele lado durante o ciclo.
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
   int index = (side == OP_BUY) ? BuySequence + 1 : SellSequence + 1;
   double nextLot = 0.0;

   if(UseObservedLotLadder)
      nextLot = ObservedLotByIndex(index);

   if(nextLot <= 0.0)
   {
      // Depois da escada observada, usa a ultima referencia disponivel
      // multiplicada pelo parametro do SET e normalizada pelo broker.
      double base = Lot;
      double observedLast = ObservedLotByIndex(11);
      if(observedLast > 0.0) base = observedLast;
      if(index > 11 && Multiplier > 0.0)
      {
         int extra = index - 11;
         nextLot = base;
         for(int i = 0; i < extra; i++)
            nextLot *= Multiplier;
      }
      else
         nextLot = base;
   }

   return(NormalizeLot(nextLot));
}

int CountOpenOrders()
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
      if(!IsEAGOLDOrder() || OrderType() != side) continue;
      count++;
   }
   return(count);
}

bool SpreadOK()
{
   if(SpreadLimit <= 0) return(true);
   double spreadPoints = (Ask - Bid) / Point;
   return(spreadPoints <= SpreadLimit);
}

bool WaitOK()
{
   if(WaitSeconds <= 0) return(true);
   if(LastTradeTime <= 0) return(true);
   return((TimeCurrent() - LastTradeTime) >= WaitSeconds);
}

//====================================================================
// PRECO MEDIO
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

   averagePrice = NormalizeDouble(weighted / totalLots, Digits);
   return(true);
}

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
   bool hasBuy = GetSideAverage(OP_BUY, buyAvg, buyLots);
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

//====================================================================
// EXPOSICAO / P&L
//====================================================================

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
      "EAGOLD v0.700  [ZEUS MODEL]\n" +
      "------------------------------------------\n" +
      "BUY   " + IntegerToString(buyCount) + " ord  " +
      DoubleToString(buyLots, 3) + " lot   P/L " + DoubleToString(buyPnl, 2) + "\n" +
      "SELL  " + IntegerToString(sellCount) + " ord  " +
      DoubleToString(sellLots, 3) + " lot   P/L " + DoubleToString(sellPnl, 2) + "\n" +
      "------------------------------------------\n" +
      "TOTAL " + IntegerToString(buyCount + sellCount) + " ord  " +
      DoubleToString(totalLots, 3) + " lot   P/L " + DoubleToString(totalPnl, 2) + "\n" +
      "Balance: " + DoubleToString(AccountBalance(), 2) +
      "   Equity: " + DoubleToString(AccountEquity(), 2) + "\n" +
      "Basket target: " + DoubleToString(BasketProfit, 2) +
      "   TP: " + DoubleToString(TakeProfit, 2);

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
// BASKET
//====================================================================

double BasketCurrentProfit()
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

void CloseBasket()
{
   RefreshRates();

   for(int i = OrdersTotal()-1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsEAGOLDOrder() || !IsOpenPosition()) continue;

      int ticket = OrderTicket();
      int type = OrderType();
      double lots = OrderLots();
      double price = (type == OP_BUY ? Bid : Ask);

      ResetLastError();
      if(!OrderClose(ticket, lots, price, 10, clrNONE))
         Print("EAGOLD ERROR - Basket close. Ticket=", ticket,
               " Error=", GetLastError());
   }

   for(int j = OrdersTotal()-1; j >= 0; j--)
   {
      if(!OrderSelect(j, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsEAGOLDOrder() || !IsPendingOrder()) continue;

      int pendingTicket = OrderTicket();
      ResetLastError();
      if(!OrderDelete(pendingTicket))
         Print("EAGOLD ERROR - Pending delete. Ticket=", pendingTicket,
               " Error=", GetLastError());
   }

   BuySequence = 0;
   SellSequence = 0;
   LastTradeTime = TimeCurrent();
   UpdateAveragePriceDisplay();
}

bool CheckBasket()
{
   if(BasketProfit <= 0.0) return(false);

   double basket = BasketCurrentProfit();
   if(basket >= BasketProfit)
   {
      Print("EAGOLD - BASKET TARGET. Current=", DoubleToString(basket,2),
            " Target=", DoubleToString(BasketProfit,2));
      CloseBasket();
      return(true);
   }
   return(false);
}

//====================================================================
// ABERTURA DE POSICAO
//====================================================================

bool SendMarket(int side, double lots, string tag)
{
   if(!SpreadOK() || !WaitOK()) return(false);
   if(MaxTrades > 0 && CountOpenOrders() >= MaxTrades) return(false);

   RefreshRates();
   double price = (side == OP_BUY ? Ask : Bid);
   lots = NormalizeLot(lots);

   if(lots <= 0.0) return(false);

   ResetLastError();
   int ticket = OrderSend(Symbol(), side, lots, NormalizeDouble(price, Digits),
                          10, 0, 0, tag, MagicNumber, 0, clrNONE);
   if(ticket < 0)
   {
      Print("EAGOLD ERROR - Market order. Side=", side == OP_BUY ? "BUY" : "SELL",
            " Lots=", DoubleToString(lots,DigitsLots),
            " Error=", GetLastError());
      return(false);
   }

   if(side == OP_BUY) BuySequence++;
   else SellSequence++;

   LastTradeTime = TimeCurrent();
   Print("EAGOLD - OPEN ", side == OP_BUY ? "BUY" : "SELL",
         " #", side == OP_BUY ? BuySequence : SellSequence,
         " Lots=", DoubleToString(lots,DigitsLots),
         " Price=", DoubleToString(price,Digits),
         " Tag=", tag);

   UpdateAveragePriceDisplay();
   return(true);
}

bool CreateOppositePending(int direction, double referencePrice, double lots,
                           int distancePoints, string tag)
{
   RefreshRates();

   int pendingType;
   double price;
   double distance = PointsToPrice(distancePoints);

   if(direction == OP_BUY)
   {
      pendingType = OP_SELLSTOP;
      price = referencePrice - distance;
   }
   else
   {
      pendingType = OP_BUYSTOP;
      price = referencePrice + distance;
   }

   price = NormalizeDouble(price, Digits);
   lots = NormalizeLot(lots);

   double stopLevel = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;
   if(direction == OP_BUY && Bid - price < stopLevel)
      price = NormalizeDouble(Bid - stopLevel, Digits);
   if(direction == OP_SELL && price - Ask < stopLevel)
      price = NormalizeDouble(Ask + stopLevel, Digits);

   ResetLastError();
   int ticket = OrderSend(Symbol(), pendingType, lots, price, 10, 0, 0,
                          tag, MagicNumber, 0, clrNONE);
   if(ticket < 0)
   {
      Print("EAGOLD ERROR - Pending order. Type=", pendingType,
            " Lots=", DoubleToString(lots,DigitsLots),
            " Price=", DoubleToString(price,Digits),
            " Error=", GetLastError());
      return(false);
   }

   Print("EAGOLD - PENDING ", direction == OP_BUY ? "BUY STOP" : "SELL STOP",
         " Ticket=", ticket,
         " Lots=", DoubleToString(lots,DigitsLots),
         " Price=", DoubleToString(price,Digits),
         " Distance=", distancePoints,
         " Tag=", tag);
   return(true);
}

bool StartSeedCycle()
{
   if(CountOpenOrders() > 0 || CountPendingOrders() > 0) return(false);
   if(!SpreadOK() || !WaitOK()) return(false);

   double firstLot = NormalizeLot(Lot);
   if(!SendMarket(OP_BUY, firstLot, "EAGOLD BUY SEED")) return(false);

   // A semente contraria e posicionada pelo FirstStep.
   RefreshRates();
   double buyPrice = Ask;
   double buyAvg, dummyLots;
   if(GetSideAverage(OP_BUY, buyAvg, dummyLots)) buyPrice = buyAvg;

   CreateOppositePending(OP_BUY, buyPrice, firstLot, FirstStep, "EAGOLD SELL SEED");
   return(true);
}

//====================================================================
// TRAILING DE PENDENTES
//====================================================================

void TrailPendingOrders()
{
   if(PendingStepTrail <= 0) return;
   RefreshRates();

   double distance = PointsToPrice(PendingStepTrail);
   double stopLevel = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;

   for(int i = OrdersTotal()-1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsEAGOLDOrder()) continue;

      int type = OrderType();
      if(type != OP_SELLSTOP && type != OP_BUYSTOP) continue;

      double desired;
      if(type == OP_SELLSTOP)
      {
         desired = NormalizeDouble(Bid - distance, Digits);
         if(Bid - desired < stopLevel)
            desired = NormalizeDouble(Bid - stopLevel, Digits);
         if(desired <= OrderOpenPrice() + Point/2.0) continue;
      }
      else
      {
         desired = NormalizeDouble(Ask + distance, Digits);
         if(desired - Ask < stopLevel)
            desired = NormalizeDouble(Ask + stopLevel, Digits);
         if(desired >= OrderOpenPrice() - Point/2.0) continue;
      }

      int ticket = OrderTicket();
      double oldPrice = OrderOpenPrice();
      ResetLastError();
      if(!OrderModify(ticket, desired, 0, 0, 0, clrNONE))
      {
         Print("EAGOLD ERROR - Pending trail. Ticket=", ticket,
               " Error=", GetLastError());
      }
      else
      {
         Print("EAGOLD - PENDING TRAIL. Ticket=", ticket,
               " Old=", DoubleToString(oldPrice,Digits),
               " New=", DoubleToString(desired,Digits),
               " Step=", PendingStepTrail);
      }
   }
}

//====================================================================
// GRID INTELIGENTE / MINI GRID
//====================================================================

bool GetExtremePrice(int side, double &price, double &lot)
{
   bool found = false;
   price = 0.0;
   lot = 0.0;

   for(int i = OrdersTotal()-1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsEAGOLDOrder() || OrderType() != side) continue;

      if(!found)
      {
         found = true;
         price = OrderOpenPrice();
         lot = OrderLots();
      }
      else if(side == OP_SELL && OrderOpenPrice() > price)
      {
         price = OrderOpenPrice();
         lot = OrderLots();
      }
      else if(side == OP_BUY && OrderOpenPrice() < price)
      {
         price = OrderOpenPrice();
         lot = OrderLots();
      }
   }
   return(found);
}

int GetSmartDistanceForSide(int side)
{
   int count = CountSidePositions(side);

   // A primeira camada usa SmartGrid1. A seguinte usa SmartGrid2.
   // MiniGrid1 fica como espacamento de seguranca para a expansao mais larga.
   if(count <= 1) return(SmartGrid1);
   if(count % 2 == 0) return(SmartGrid2);
   return(SmartGrid1);
}

void ManageSideGrid(int side)
{
   if(MaxTrades > 0 && CountOpenOrders() >= MaxTrades) return;
   if(!SpreadOK() || !WaitOK()) return;
   if(CountSidePositions(side) <= 0) return;

   double extremePrice, lastLot;
   if(!GetExtremePrice(side, extremePrice, lastLot)) return;

   RefreshRates();

   int smartDistance = GetSmartDistanceForSide(side);
   double triggerDistance = PointsToPrice(smartDistance);

   bool trigger = false;
   if(side == OP_SELL)
   {
      // SELL esta contra o movimento quando o Ask sobe acima do ultimo nivel.
      if(Ask >= extremePrice + triggerDistance)
         trigger = true;
   }
   else
   {
      // BUY esta contra o movimento quando o Bid cai abaixo do ultimo nivel.
      if(Bid <= extremePrice - triggerDistance)
         trigger = true;
   }

   if(!trigger) return;

   double nextLot = NextLotForSide(side);
   string tag = (side == OP_BUY ? "EAGOLD BUY GRID" : "EAGOLD SELL GRID");
   SendMarket(side, nextLot, tag);
}

void ManageAdaptiveGrid()
{
   // O modelo e simetrico: qualquer perna pode acumular quando fica contra o movimento.
   ManageSideGrid(OP_BUY);
   ManageSideGrid(OP_SELL);
}

//====================================================================
// TAKE INDIVIDUAL
//====================================================================

void ManageIndividualTake()
{
   if(TakeProfit <= 0.0) return;
   RefreshRates();

   for(int i = OrdersTotal()-1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsEAGOLDOrder() || !IsOpenPosition()) continue;

      double move;
      if(OrderType() == OP_BUY) move = Bid - OrderOpenPrice();
      else move = OrderOpenPrice() - Ask;

      if(move < TakeProfit) continue;

      int ticket = OrderTicket();
      int side = OrderType();
      double lots = OrderLots();
      double price = (side == OP_BUY ? Bid : Ask);

      ResetLastError();
      if(!OrderClose(ticket, lots, price, 10, clrNONE))
      {
         Print("EAGOLD ERROR - Individual TP. Ticket=", ticket,
               " Error=", GetLastError());
         continue;
      }

      Print("EAGOLD - INDIVIDUAL TP. Ticket=", ticket,
            " Side=", side == OP_BUY ? "BUY" : "SELL",
            " Move=", DoubleToString(move,2),
            " TP=", DoubleToString(TakeProfit,2));

      // A proxima operacao do mesmo lado so nasce apos o fechamento da atual.
      // O lote segue a sequencia daquele lado.
      double nextLot = NextLotForSide(side);
      SendMarket(side, nextLot,
                 side == OP_BUY ? "EAGOLD BUY SUCCESSOR" : "EAGOLD SELL SUCCESSOR");
   }
}

//====================================================================
// RECUPERACAO DOS CONTADORES APOS RELOAD
//====================================================================

void InitializeSequences()
{
   BuySequence = CountSidePositions(OP_BUY);
   SellSequence = CountSidePositions(OP_SELL);

   // Nao tentamos inferir ordens ja fechadas: a sequencia e uma referencia
   // de ciclo. O basket reinicia explicitamente os contadores.
   LastTradeTime = 0;
}

void DeletePanel()
{
   DeleteObjectIfExists(PanelName);
}

//====================================================================
// INIT / DEINIT
//====================================================================

int OnInit()
{
   DeleteAveragePriceDisplay();
   DeletePanel();
   InitializeSequences();

   Print("==============================================================");
   Print("EAGOLD v0.700 - ZEUS INTERPRETATION MODEL");
   Print("Lot=", DoubleToString(Lot,DigitsLots),
         " Multiplier=", DoubleToString(Multiplier,2),
         " LotIncrement=", DoubleToString(LotIncrement,DigitsLots),
         " MaxOpenLot=", DoubleToString(MaxOpenLot,DigitsLots));
   Print("TP=", DoubleToString(TakeProfit,2),
         " BasketProfit=", DoubleToString(BasketProfit,2));
   Print("FirstStep=", FirstStep,
         " MiniGrid1=", MiniGrid1,
         " MiniGrid2=", MiniGrid2,
         " PendingStepTrail=", PendingStepTrail);
   Print("SmartGrid1=", SmartGrid1,
         " SmartGrid2=", SmartGrid2,
         " MaxTrades=", MaxTrades);
   Print("ObservedLotLadder=", UseObservedLotLadder ? "ON" : "OFF");
   Print("==============================================================");

   UpdateAveragePriceDisplay();
   CreateOrUpdatePanel();
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   DeleteAveragePriceDisplay();
   DeletePanel();
   Print("EAGOLD v0.700 DEINITIALIZED. Reason=", reason);
}

//====================================================================
// TICK
//====================================================================

void OnTick()
{
   if(CheckBasket())
   {
      CreateOrUpdatePanel();
      return;
   }

   TrailPendingOrders();
   ManageIndividualTake();
   ManageAdaptiveGrid();

   if(CountOpenOrders() == 0 && CountPendingOrders() == 0)
      StartSeedCycle();

   UpdateAveragePriceDisplay();
   CreateOrUpdatePanel();
}

//+------------------------------------------------------------------+
