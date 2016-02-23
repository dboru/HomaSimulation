#!/usr/bin/Rscript
library(reshape2)
library(ggplot2)
library(gridExtra)
library(plyr)

# Plots the stretch vs. unsched bytes from text data files generated by PlotDigeter.py script
stretchVsSize <- read.table("stretchVsTransport.txt", na.strings = "NA",
    col.names=c('TransportType', 'LoadFactor', 'WorkLoad', 'MsgSizeRange', 'SizeCntPercent', 'BytesPercent',
        'UnschedBytes', 'MeanStretch', 'MedianStretch', 'TailStretch'),
    header=TRUE)
stretchVsSize$LoadFactor <- factor(stretchVsSize$LoadFactor)
stretchVsSize$TransportType <- factor(stretchVsSize$TransportType)

avgStretchVsSize <- subset(stretchVsSize,
    !is.na(MeanStretch) & !(MsgSizeRange %in% c('Huge', 'OverAllSizes')),
    select=c('TransportType', 'LoadFactor', 'WorkLoad', 'MsgSizeRange', 'SizeCntPercent', 'BytesPercent', 'UnschedBytes', 'MeanStretch'))
avgStretchVsSize <- ddply(avgStretchVsSize, .(TransportType, LoadFactor, WorkLoad, UnschedBytes), transform,
    SizeCumPercent = round(cumsum(SizeCntPercent), 2), BytesCumPercent = round(cumsum(BytesPercent), 2))
avgStretchVsSize$MsgSizeRange <- as.numeric(as.character(avgStretchVsSize$MsgSizeRange))

medianStretchVsSize <- subset(stretchVsSize,
    !is.na(MedianStretch) & !(MsgSizeRange %in% c('Huge', 'OverAllSizes')),
    select=c('TransportType', 'LoadFactor', 'WorkLoad', 'MsgSizeRange', 'SizeCntPercent', 'BytesPercent', 'UnschedBytes', 'MedianStretch'))
medianStretchVsSize <- ddply(medianStretchVsSize, .(TransportType, LoadFactor, WorkLoad, UnschedBytes), transform,
    SizeCumPercent = round(cumsum(SizeCntPercent), 2), BytesCumPercent = round(cumsum(BytesPercent), 2))
medianStretchVsSize$MsgSizeRange <- as.numeric(as.character(medianStretchVsSize$MsgSizeRange))

tailStretchVsSize <- subset(stretchVsSize,
    !is.na(TailStretch) & !(MsgSizeRange %in% c('Huge', 'OverAllSizes')),
    select=c('TransportType', 'LoadFactor', 'WorkLoad', 'MsgSizeRange', 'SizeCntPercent', 'BytesPercent', 'UnschedBytes', 'TailStretch'))
tailStretchVsSize <- ddply(tailStretchVsSize, .(TransportType, LoadFactor, WorkLoad, UnschedBytes), transform,
    SizeCumPercent = round(cumsum(SizeCntPercent), 2), BytesCumPercent = round(cumsum(BytesPercent), 2))
tailStretchVsSize$MsgSizeRange <- as.numeric(as.character(tailStretchVsSize$MsgSizeRange))

textSize <- 35
titleSize <- 30
yLimit <- 25

hasPseudoIdeal = !empty(subset(stretchVsSize, TransportType %in% c('PseudoIdeal')))
normalizedGraph = FALSE
for (rho in unique(avgStretchVsSize$LoadFactor)) {
    i <- 0
    avgStretchPlot = list()
    for (transport in sort(unique(stretchVsSize$TransportType))) {
        for (workload in levels(avgStretchVsSize$WorkLoad)) {
            # Use CDF as the x axis
            i <- i+1
            tmp <- subset(avgStretchVsSize, WorkLoad==workload & LoadFactor==rho & TransportType==transport,
                select=c('LoadFactor', 'WorkLoad', 'MsgSizeRange', 'SizeCntPercent', 'SizeCumPercent',
                'TransportType', 'MeanStretch', 'UnschedBytes'))
            if (hasPseudoIdeal && normalizedGraph) {
                pseudoIdealDF = subset(avgStretchVsSize, WorkLoad==workload & LoadFactor==rho & TransportType=='PseudoIdeal',
                    select=c('LoadFactor', 'WorkLoad', 'MsgSizeRange', 'SizeCntPercent', 'SizeCumPercent', 'TransportType',
                    'MeanStretch', 'UnschedBytes'))
                if (transport != 'PseudoIdeal') {
                    tmp$MeanStretch <- tmp$MeanStretch / pseudoIdealDF$MeanStretch
                    plotTitle = sprintf("Normalized MeanStrech VS. Cummulative Msg Size Percent, transport:%s, unsched:%d,
                        loadfactor:%s, workload:%s", transport, avgStretchVsSize$UnschedBytes[1], rho, workload)
                    yLab = 'MeanStretch (Normalized to PseudoIdeal)'
                } else {
                    plotTitle = sprintf("MeanStrech VS. Cummulative Msg Size Percent, transport:%s, unsched:%d,
                        loadfactor:%s, workload:%s", transport, avgStretchVsSize$UnschedBytes[1], rho, workload)
                    yLab = 'MeanStretch'
                }
            } else {
                plotTitle = sprintf("MeanStrech VS. Cummulative Msg Size Percent, transport:%s, unsched:%d,
                    loadfactor:%s, workload:%s", transport, avgStretchVsSize$UnschedBytes[1], rho, workload)
                yLab = 'MeanStretch'
            }

            # You might ask why I'm using "x=SizeCumPercent-SizeCntPercent/200" in the plot. The reason is that ggplot geom_bar is so
            # dumb and I was not able to shift the bars to the write while setting the width of each bar to be equal to it's size
            # probability. So I ended up manaully shift the bars to the the left for half of the probability and setting the width
            # equal to the probability
            avgStretchPlot[[i]] <- ggplot(tmp, aes(x=SizeCumPercent-SizeCntPercent/2, y=MeanStretch, width=SizeCntPercent)) +
                geom_bar(stat="identity", position="identity", fill="white", color="darkgreen") +
                geom_text(data=tmp, aes(x=SizeCumPercent, y=pmin(yLimit/2, MeanStretch/2), 
                    label=paste(MsgSizeRange, ":", format(MeanStretch, digits=3))), angle=90, size=11)

            if (hasPseudoIdeal && !normalizedGraph) {
                pseudoIdealDF = subset(avgStretchVsSize, WorkLoad==workload & LoadFactor==rho & TransportType=='PseudoIdeal',
                    select=c('LoadFactor', 'WorkLoad', 'MsgSizeRange', 'SizeCntPercent', 'SizeCumPercent', 'TransportType',
                    'MeanStretch', 'UnschedBytes'))
                avgStretchPlot[[i]] <- avgStretchPlot[[i]] +
                    geom_step(data=pseudoIdealDF,
                        aes(x=SizeCumPercent, y=MeanStretch, width=SizeCntPercent), direction='vh', color='red', size=2)
            }

            plotTitle <- paste(append(unlist(strsplit(plotTitle, split='')), '\n', as.integer(nchar(plotTitle)/2)), sep='', collapse='') 
            avgStretchPlot[[i]] <- avgStretchPlot[[i]] +
                theme(text = element_text(size=textSize, face="bold"), axis.text.x = element_text(angle=75, vjust=0.5),
                    strip.text.x = element_text(size = textSize), strip.text.y = element_text(size = textSize),
                    plot.title = element_text(size = titleSize)) +
                scale_x_continuous(breaks = tmp$SizeCumPercent) +
                coord_cartesian(ylim=c(0, min(yLimit, max(tmp$MeanStretch, na.rm=TRUE)))) +
                labs(title = plotTitle, x = "Cumulative Msg Size Percent", y = yLab)

            # Use CBF as the x axis
            i <- i+1
            tmp <- subset(avgStretchVsSize, WorkLoad==workload & LoadFactor==rho & TransportType==transport,
                select=c('LoadFactor', 'WorkLoad', 'MsgSizeRange', 'BytesPercent', 'BytesCumPercent',
                'TransportType', 'MeanStretch', 'UnschedBytes'))
            if (hasPseudoIdeal && normalizedGraph) {
                pseudoIdealDF = subset(avgStretchVsSize, WorkLoad==workload & LoadFactor==rho & TransportType=='PseudoIdeal',
                    select=c('LoadFactor', 'WorkLoad', 'MsgSizeRange', 'BytesPercent', 'BytesCumPercent', 'TransportType',
                    'MeanStretch', 'UnschedBytes'))
                if (transport != 'PseudoIdeal') {
                    tmp$MeanStretch <- tmp$MeanStretch / pseudoIdealDF$MeanStretch
                    plotTitle = sprintf("Normalized MeanStrech VS. Cummulative Msg Size Percent, transport:%s, unsched:%d,
                        loadfactor:%s, workload:%s", transport, avgStretchVsSize$UnschedBytes[1], rho, workload)
                    yLab = 'MeanStretch (Normalized to PseudoIdeal)'
                } else {
                    plotTitle = sprintf("MeanStrech VS. Cummulative Msg Size Percent, transport:%s, unsched:%d,
                        loadfactor:%s, workload:%s", transport, avgStretchVsSize$UnschedBytes[1], rho, workload)
                    yLab = 'MeanStretch'
                }
            } else {
                plotTitle = sprintf("MeanStrech VS. Cummulative Msg Size Percent, transport:%s, unsched:%d,
                    loadfactor:%s, workload:%s", transport, avgStretchVsSize$UnschedBytes[1], rho, workload)
                yLab = 'MeanStretch'
            }

            avgStretchPlot[[i]] <- ggplot(tmp, aes(x=BytesCumPercent-BytesPercent/2, y=MeanStretch, width=BytesPercent)) +
                geom_bar(stat="identity", position="identity", fill="white", color="darkgreen") +
                geom_text(data=tmp, aes(x=BytesCumPercent, y=pmin(yLimit/2, MeanStretch/2), 
                    label=paste(MsgSizeRange, ":", format(MeanStretch, digits=3))), angle=90, size=11)
            if (hasPseudoIdeal && !normalizedGraph)  {
                pseudoIdealDF = subset(avgStretchVsSize, WorkLoad==workload & LoadFactor==rho & TransportType=='PseudoIdeal',
                    select=c('LoadFactor', 'WorkLoad', 'MsgSizeRange', 'BytesPercent', 'BytesCumPercent', 'TransportType',
                    'MeanStretch', 'UnschedBytes'))

                avgStretchPlot[[i]] <- avgStretchPlot[[i]] +
                    geom_step(data=pseudoIdealDF,
                        aes(x=BytesCumPercent, y=MeanStretch, width=BytesPercent), direction='vh', color='red', size=2)
            }

            plotTitle <- paste(append(unlist(strsplit(plotTitle, split='')), '\n', as.integer(nchar(plotTitle)/2)), sep='', collapse='') 
            avgStretchPlot[[i]] <- avgStretchPlot[[i]] +
            theme(text = element_text(size=textSize, face="bold"), axis.text.x = element_text(angle=75, vjust=0.5),
                strip.text.x = element_text(size = textSize), strip.text.y = element_text(size = textSize),
                plot.title = element_text(size = titleSize)) +
            scale_x_continuous(breaks = tmp$BytesCumPercent) +
            coord_cartesian(ylim=c(0, min(yLimit, max(tmp$MeanStretch, na.rm=TRUE)))) +
            labs(title = plotTitle, x = "Cumulative Bytes Percent", y = yLab)

        }
    }
    pdf(sprintf("plots/MeanStretchVsTransport_rho%s.pdf", rho),
        width=100*length(unique(avgStretchVsSize$WorkLoad)),
        height=15*length(unique(stretchVsSize$TransportType)))
    args.list <- c(avgStretchPlot, list(ncol=2*length(unique(avgStretchVsSize$WorkLoad))))
    do.call(grid.arrange, args.list)
    dev.off()
}

for (rho in unique(medianStretchVsSize$LoadFactor)) {
    i <- 0
    medianStretchPlot = list()
    for (transport in sort(unique(stretchVsSize$TransportType))) {
        for (workload in levels(medianStretchVsSize$WorkLoad)) {
            # Use CDF as the x axis
            i <- i+1
            tmp <- subset(medianStretchVsSize, WorkLoad==workload & LoadFactor==rho & TransportType==transport,
                select=c('LoadFactor', 'WorkLoad', 'MsgSizeRange', 'SizeCntPercent', 'SizeCumPercent',
                'TransportType', 'MedianStretch', 'UnschedBytes'))

            if (hasPseudoIdeal && normalizedGraph) {
                pseudoIdealDF = subset(medianStretchVsSize, WorkLoad==workload & LoadFactor==rho & TransportType=='PseudoIdeal',
                    select=c('LoadFactor', 'WorkLoad', 'MsgSizeRange', 'SizeCntPercent', 'SizeCumPercent', 'TransportType',
                    'MedianStretch', 'UnschedBytes'))
                if (transport != 'PseudoIdeal') {
                    tmp$MedianStretch <- tmp$MedianStretch / pseudoIdealDF$MedianStretch
                    plotTitle = sprintf("Normalized MedianStrech VS. Cummulative Msg Size Percent, transport:%s, unsched:%d,
                        loadfactor:%s, workload:%s", transport, medianStretchVsSize$UnschedBytes[1], rho, workload)
                    yLab = 'MedianStretch (Normalized to PseudoIdeal)'
                } else {
                    plotTitle = sprintf("MedianStrech VS. Cummulative Msg Size Percent, transport:%s, unsched:%d,
                        loadfactor:%s, workload:%s", transport, medianStretchVsSize$UnschedBytes[1], rho, workload)
                    yLab = 'MedianStretch'
                }
            } else {
                plotTitle = sprintf("MedianStrech VS. Cummulative Msg Size Percent, transport:%s, unsched:%d,
                    loadfactor:%s, workload:%s", transport, medianStretchVsSize$UnschedBytes[1], rho, workload)
                yLab = 'MedianStretch'
            }

            # You might ask why I'm using "x=SizeCumPercent-SizeCntPercent/200" in the plot. The reason is that ggplot geom_bar is so
            # dumb and I was not able to shift the bars to the write while setting the width of each bar to be equal to it's size
            # probability. So I ended up manaully shift the bars to the the left for half of the probability and setting the width
            # equal to the probability
            medianStretchPlot[[i]] <- ggplot(tmp, aes(x=SizeCumPercent-SizeCntPercent/2, y=MedianStretch, width=SizeCntPercent)) +
                geom_bar(stat="identity", position="identity", fill="white", color="darkgreen") +
                geom_text(data=tmp, aes(x=SizeCumPercent, y=pmin(yLimit/2, MedianStretch/2), 
                    label=paste(MsgSizeRange, ":", format(MedianStretch, digits=3))), angle=90, size=11)
      
            if (hasPseudoIdeal && !normalizedGraph) {
                pseudoIdealDF = subset(medianStretchVsSize, WorkLoad==workload & LoadFactor==rho & TransportType=='PseudoIdeal',
                    select=c('LoadFactor', 'WorkLoad', 'MsgSizeRange', 'SizeCntPercent', 'SizeCumPercent', 'TransportType',
                    'MedianStretch', 'UnschedBytes'))

                medianStretchPlot[[i]] <- medianStretchPlot[[i]] +
                    geom_step(data=pseudoIdealDF,
                        aes(x=SizeCumPercent, y=MedianStretch, width=SizeCntPercent), direction='vh', color='red', size=2)

            }

            plotTitle <- paste(append(unlist(strsplit(plotTitle, split='')), '\n', as.integer(nchar(plotTitle)/2)), sep='', collapse='') 
            medianStretchPlot[[i]] <- medianStretchPlot[[i]] +
                theme(text = element_text(size=textSize, face="bold"), axis.text.x = element_text(angle=75, vjust=0.5),
                    strip.text.x = element_text(size = textSize), strip.text.y = element_text(size = textSize),
                    plot.title = element_text(size = titleSize)) +
                scale_x_continuous(breaks = tmp$SizeCumPercent) +
                coord_cartesian(ylim=c(0, min(yLimit, max(tmp$MedianStretch, na.rm=TRUE)))) +
                labs(title = plotTitle, x = "Cumulative Msg Size Percent", y = yLab)

            # Use CBF as the x axis
            i <- i+1
            tmp <- subset(medianStretchVsSize, WorkLoad==workload & LoadFactor==rho & TransportType==transport,
                select=c('LoadFactor', 'WorkLoad', 'MsgSizeRange', 'BytesPercent', 'BytesCumPercent',
                'TransportType', 'MedianStretch', 'UnschedBytes'))

            if (hasPseudoIdeal && normalizedGraph) {
                pseudoIdealDF = subset(medianStretchVsSize, WorkLoad==workload & LoadFactor==rho & TransportType=='PseudoIdeal',
                    select=c('LoadFactor', 'WorkLoad', 'MsgSizeRange', 'BytesPercent', 'BytesCumPercent', 'TransportType',
                    'MedianStretch', 'UnschedBytes'))
                if (transport != 'PseudoIdeal') {
                    tmp$MedianStretch <- tmp$MedianStretch / pseudoIdealDF$MedianStretch
                    plotTitle = sprintf("Normalized MedianStrech VS. Cummulative Msg Size Percent, transport:%s, unsched:%d,
                        loadfactor:%s, workload:%s", transport, medianStretchVsSize$UnschedBytes[1], rho, workload)
                    yLab = 'MedianStretch (Normalized to PseudoIdeal)'
                } else {
                    plotTitle = sprintf("MedianStrech VS. Cummulative Msg Size Percent, transport:%s, unsched:%d,
                        loadfactor:%s, workload:%s", transport, medianStretchVsSize$UnschedBytes[1], rho, workload)
                    yLab = 'MedianStretch'
                }
            } else {
                plotTitle = sprintf("MedianStrech VS. Cummulative Msg Size Percent, transport:%s, unsched:%d,
                    loadfactor:%s, workload:%s", transport, medianStretchVsSize$UnschedBytes[1], rho, workload)
                yLab = 'MedianStretch'
            }

            medianStretchPlot[[i]] <- ggplot(tmp, aes(x=BytesCumPercent-BytesPercent/2, y=MedianStretch, width=BytesPercent)) +
                geom_bar(stat="identity", position="identity", fill="white", color="darkgreen") +
                geom_text(data=tmp, aes(x=BytesCumPercent, y=pmin(yLimit/2, MedianStretch/2), 
                    label=paste(MsgSizeRange, ":", format(MedianStretch, digits=3))), angle=90, size=11)

            if (hasPseudoIdeal && !normalizedGraph) {
                pseudoIdealDF = subset(medianStretchVsSize, WorkLoad==workload & LoadFactor==rho & TransportType=='PseudoIdeal',
                    select=c('LoadFactor', 'WorkLoad', 'MsgSizeRange', 'BytesPercent', 'BytesCumPercent', 'TransportType',
                    'MedianStretch', 'UnschedBytes'))
                medianStretchPlot[[i]] <- medianStretchPlot[[i]] +
                    geom_step(data=pseudoIdealDF,
                        aes(x=BytesCumPercent, y=MedianStretch, width=BytesPercent), direction='vh', color='red', size=2)

            }

            plotTitle <- paste(append(unlist(strsplit(plotTitle, split='')), '\n', as.integer(nchar(plotTitle)/2)), sep='', collapse='') 
            medianStretchPlot[[i]] <- medianStretchPlot[[i]] +
                theme(text = element_text(size=textSize, face="bold"), axis.text.x = element_text(angle=75, vjust=0.5),
                    strip.text.x = element_text(size = textSize), strip.text.y = element_text(size = textSize),
                    plot.title = element_text(size = titleSize)) +
                scale_x_continuous(breaks = tmp$BytesCumPercent) +
                coord_cartesian(ylim=c(0, min(yLimit, max(tmp$MedianStretch, na.rm=TRUE)))) +
                labs(title = plotTitle, x = "Cumulative Bytes Percent", y = yLab)
        }
    }
    pdf(sprintf("plots/MedianStretchVsTransport_rho%s.pdf", rho),
        width=100*length(unique(medianStretchVsSize$WorkLoad)),
        height=15*length(unique(stretchVsSize$TransportType)))
    args.list <- c(medianStretchPlot, list(ncol=2*length(unique(medianStretchVsSize$WorkLoad))))
    do.call(grid.arrange, args.list)
    dev.off()
}

for (rho in unique(tailStretchVsSize$LoadFactor)) {
    i <- 0
    tailStretchPlot = list()
    for (transport in sort(unique(stretchVsSize$TransportType))) {
        for (workload in levels(tailStretchVsSize$WorkLoad)) {
            # Use CDF as the x axis
            i <- i+1
            tmp <- subset(tailStretchVsSize, WorkLoad==workload & LoadFactor==rho & TransportType==transport,
                select=c('LoadFactor', 'WorkLoad', 'MsgSizeRange', 'SizeCntPercent', 'SizeCumPercent',
                'TransportType', 'TailStretch', 'UnschedBytes'))

            if (hasPseudoIdeal && normalizedGraph) {
                pseudoIdealDF = subset(tailStretchVsSize, WorkLoad==workload & LoadFactor==rho & TransportType=='PseudoIdeal',
                    select=c('LoadFactor', 'WorkLoad', 'MsgSizeRange', 'SizeCntPercent', 'SizeCumPercent', 'TransportType',
                    'TailStretch', 'UnschedBytes'))
                if (transport != 'PseudoIdeal') {
                    tmp$TailStretch <- tmp$TailStretch / pseudoIdealDF$TailStretch
                    plotTitle = sprintf("Normalized TailStrech VS. Cummulative Msg Size Percent, transport:%s, unsched:%d,
                        loadfactor:%s, workload:%s", transport, tailStretchVsSize$UnschedBytes[1], rho, workload)
                    yLab = 'TailStretch (Normalized to PseudoIdeal)'
                } else {
                    plotTitle = sprintf("TailStrech VS. Cummulative Msg Size Percent, transport:%s, unsched:%d,
                        loadfactor:%s, workload:%s", transport, tailStretchVsSize$UnschedBytes[1], rho, workload)
                    yLab = 'TailStretch'
                }
            } else {
                plotTitle = sprintf("TailStrech VS. Cummulative Msg Size Percent, transport:%s, unsched:%d,
                    loadfactor:%s, workload:%s", transport, tailStretchVsSize$UnschedBytes[1], rho, workload)
                yLab = 'TailStretch'
            }

            # You might ask why I'm using "x=SizeCumPercent-SizeCntPercent/200" in the plot. The reason is that ggplot geom_bar is so
            # dumb and I was not able to shift the bars to the write while setting the width of each bar to be equal to it's size
            # probability. So I ended up manaully shift the bars to the the left for half of the probability and setting the width
            # equal to the probability
            tailStretchPlot[[i]] <- ggplot(tmp, aes(x=SizeCumPercent-SizeCntPercent/2, y=TailStretch, width=SizeCntPercent)) +
                geom_bar(stat="identity", position="identity", fill="white", color="darkgreen") +
                geom_text(data=tmp, aes(x=SizeCumPercent, y=pmin(yLimit/2, TailStretch/2), 
                    label=paste(MsgSizeRange, ":", format(TailStretch, digits=3))), angle=90, size=11)

            if (hasPseudoIdeal && !normalizedGraph) {
                pseudoIdealDF = subset(tailStretchVsSize, WorkLoad==workload & LoadFactor==rho & TransportType=='PseudoIdeal',
                    select=c('LoadFactor', 'WorkLoad', 'MsgSizeRange', 'SizeCntPercent', 'SizeCumPercent', 'TransportType',
                    'TailStretch', 'UnschedBytes'))
                tailStretchPlot[[i]] <- tailStretchPlot[[i]] +
                    geom_step(data=pseudoIdealDF,
                        aes(x=SizeCumPercent, y=TailStretch, width=SizeCntPercent), direction='vh', color='red', size=2)
            }

            tailStretchPlot[[i]] <- tailStretchPlot[[i]] +
                theme(text = element_text(size=textSize, face="bold"), axis.text.x = element_text(angle=75, vjust=0.5),
                    strip.text.x = element_text(size = textSize), strip.text.y = element_text(size = textSize),
                    plot.title = element_text(size = titleSize)) +
                scale_x_continuous(breaks = tmp$SizeCumPercent) +
                coord_cartesian(ylim=c(0, min(yLimit, max(tmp$TailStretch, na.rm=TRUE)))) +
                labs(title = plotTitle, x = "Cumulative Msg Size Percent", y = yLab)

            # Use CBF as the x axis
            i <- i+1
            tmp <- subset(tailStretchVsSize, WorkLoad==workload & LoadFactor==rho & TransportType==transport,
                select=c('LoadFactor', 'WorkLoad', 'MsgSizeRange', 'BytesPercent', 'BytesCumPercent',
                'TransportType', 'TailStretch', 'UnschedBytes'))

            plotTitle <- paste(append(unlist(strsplit(plotTitle, split='')), '\n', as.integer(nchar(plotTitle)/2)), sep='', collapse='') 
            if (hasPseudoIdeal && normalizedGraph) {
                pseudoIdealDF = subset(tailStretchVsSize, WorkLoad==workload & LoadFactor==rho & TransportType=='PseudoIdeal',
                    select=c('LoadFactor', 'WorkLoad', 'MsgSizeRange', 'BytesPercent', 'BytesCumPercent', 'TransportType',
                    'TailStretch', 'UnschedBytes'))
                if (transport != 'PseudoIdeal') {
                    tmp$TailStretch <- tmp$TailStretch / pseudoIdealDF$TailStretch
                    plotTitle = sprintf("Normalized TailStrech VS. Cummulative Msg Size Percent, transport:%s, unsched:%d,
                        loadfactor:%s, workload:%s", transport, tailStretchVsSize$UnschedBytes[1], rho, workload)
                    yLab = 'TailStretch (Normalized to PseudoIdeal)'
                } else {
                    plotTitle = sprintf("TailStrech VS. Cummulative Msg Size Percent, transport:%s, unsched:%d,
                        loadfactor:%s, workload:%s", transport, tailStretchVsSize$UnschedBytes[1], rho, workload)
                    yLab = 'TailStretch'
                }
            } else {
                plotTitle = sprintf("TailStrech VS. Cummulative Msg Size Percent, transport:%s, unsched:%d,
                    loadfactor:%s, workload:%s", transport, tailStretchVsSize$UnschedBytes[1], rho, workload)
                yLab = 'TailStretch'
            }

            tailStretchPlot[[i]] <- ggplot(tmp, aes(x=BytesCumPercent-BytesPercent/2, y=TailStretch, width=BytesPercent)) +
                geom_bar(stat="identity", position="identity", fill="white", color="darkgreen") +
                geom_text(data=tmp, aes(x=BytesCumPercent, y=pmin(yLimit/2, TailStretch/2), 
                    label=paste(MsgSizeRange, ":", format(TailStretch, digits=3))), angle=90, size=11)

            if (hasPseudoIdeal && !normalizedGraph) {
                pseudoIdealDF = subset(tailStretchVsSize, WorkLoad==workload & LoadFactor==rho & TransportType=='PseudoIdeal',
                    select=c('LoadFactor', 'WorkLoad', 'MsgSizeRange', 'BytesPercent', 'BytesCumPercent', 'TransportType',
                    'TailStretch', 'UnschedBytes'))
                tailStretchPlot[[i]] <- tailStretchPlot[[i]] +
                     geom_step(data=pseudoIdealDF,
                        aes(x=BytesCumPercent, y=TailStretch, width=BytesPercent), direction='vh', color='red', size=2)
            }

            plotTitle <- paste(append(unlist(strsplit(plotTitle, split='')), '\n', as.integer(nchar(plotTitle)/2)), sep='', collapse='') 
            tailStretchPlot[[i]] <- tailStretchPlot[[i]] +
                theme(text = element_text(size=textSize, face="bold"), axis.text.x = element_text(angle=75, vjust=0.5),
                    strip.text.x = element_text(size = textSize), strip.text.y = element_text(size = textSize),
                    plot.title = element_text(size = titleSize)) +
                scale_x_continuous(breaks = tmp$BytesCumPercent) +
                coord_cartesian(ylim=c(0, min(yLimit, max(tmp$TailStretch, na.rm=TRUE)))) +
                labs(title = plotTitle, x = "Cumulative Bytes Percent", y = yLab)
        }
    }
    pdf(sprintf("plots/TailStretchVsTransport_rho%s.pdf", rho),
        width=100*length(unique(tailStretchVsSize$WorkLoad)),
        height=15*length(unique(stretchVsSize$TransportType)))
    args.list <- c(tailStretchPlot, list(ncol=2*length(unique(tailStretchVsSize$WorkLoad))))
    do.call(grid.arrange, args.list)
    dev.off()
}