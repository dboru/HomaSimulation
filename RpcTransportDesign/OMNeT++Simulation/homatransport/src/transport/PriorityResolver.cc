/*
 * PriorityResolver.cc
 *
 *  Created on: Dec 23, 2015
 *      Author: behnamm
 */

#include "PriorityResolver.h"

PriorityResolver::PriorityResolver(HomaConfigDepot* homaConfig,
        WorkloadEstimator* distEstimator)
    : lastCbfCapMsgSize(UINT32_MAX)
    , cdf(&distEstimator->cdfFromFile)
    , cbf(&distEstimator->cbfFromFile)
    , cbfLastCapBytes(&distEstimator->cbfLastCapBytesFromFile)
    , prioCutOffsFromCdf()
    , prioCutOffsFromCbf()
    , prioCutOffsExpCbf()
    , prioCutOffsExpCdf()
    , prioCutOffsHeadTailFirst()
    , prioCutOffsHeadTailFirstExp()
    , distEstimator(distEstimator)
    , homaConfig(homaConfig)
{
    setCdfPrioCutOffs();
    setCbfPrioCutOffs();
    setExpFromCdfPrioCutOffs();
    setExpFromCbfPrioCutOffs();

    HomaPkt dataPkt = HomaPkt();
    dataPkt.setPktType(PktType::SCHED_DATA);
    maxSchedPktDataBytes = MAX_ETHERNET_PAYLOAD_BYTES -
        IP_HEADER_SIZE - UDP_HEADER_SIZE - dataPkt.headerSize();
}

std::vector<uint16_t>
PriorityResolver::getUnschedPktsPrio(PrioResolutionMode prioMode,
    const OutboundMessage* outbndMsg)
{
    uint32_t msgSize = outbndMsg->msgSize;
    std::vector<uint32_t>* cutOffVec = NULL;
        switch (prioMode) {
        case PrioResolutionMode::FIXED_UNSCHED: {
            std::vector<uint16_t> unschedPktsPrio(
                outbndMsg->reqUnschedDataVec.size(), 0);
            return unschedPktsPrio;
        }
        case PrioResolutionMode::SIMULATED_SRBF: {
            std::vector<uint16_t> unschedPktsPrio(
                outbndMsg->reqUnschedDataVec.size());
            for (size_t i = 0; i < unschedPktsPrio.size(); i++) {
                unschedPktsPrio[i] = downCast<uint16_t>(
                    std::min((int)(unschedPktsPrio.size() - i - 1),
                    (int)homaConfig->prioResolverPrioLevels - 1));
            }
            return unschedPktsPrio;
        }
        case PrioResolutionMode::SMF_CBF_BASED: {
            cutOffVec = &prioCutOffsFromCbf;
            break;
        }
        case PrioResolutionMode::HEAD_TAIL_BYTES_FIRST_EQUAL_BYTES: {
            cutOffVec = &prioCutOffsHeadTailFirst;
            break;
        }
        case PrioResolutionMode::HEAD_TAIL_BYTES_FIRST_EXP_BYTES: {
            cutOffVec = &prioCutOffsHeadTailFirstExp;
            break;
        }
        case PrioResolutionMode::HEAD_TAIL_BYTES_FIRST_EQUAL_COUNTS: {
            cutOffVec = &prioCutOffsFromCdf;
            break;
        }
        case PrioResolutionMode::HEAD_TAIL_BYTES_FIRST_EXP_COUNTS: {
            cutOffVec = &prioCutOffsExpCdf;
            break;
        }
        case PrioResolutionMode::STATIC_FROM_CDF:
            cutOffVec = &prioCutOffsFromCdf;
            break;
        case PrioResolutionMode::STATIC_FROM_CBF:
            cutOffVec = &prioCutOffsFromCbf;
            break;
        case PrioResolutionMode::STATIC_EXP_CDF:
            cutOffVec = &prioCutOffsExpCdf;
            break;
        case PrioResolutionMode::STATIC_EXP_CBF:
            cutOffVec = &prioCutOffsExpCbf;
            break;
        default:
            throw cRuntimeError("Invalid priority mode: prioMode(%d)", prioMode);
    }

    size_t mid, high, low;
    low = 0;
    high = cutOffVec->size() - 1;
    while(low < high) {
        mid = (high + low) / 2;
        if (msgSize <= cutOffVec->at(mid)) {
            high = mid;
        } else {
            low = mid + 1;
        }
    }
    std::vector<uint16_t> unschedPktsPrio(
        outbndMsg->reqUnschedDataVec.size(), (uint16_t)high);
    return unschedPktsPrio;
}

uint16_t
PriorityResolver::getSchedPktPrio(PrioResolutionMode prioMode,
    const InboundMessage* inbndMsg)
{
    uint32_t msgSize = inbndMsg->msgSize;
    std::vector<uint32_t>* cutOffVec = NULL;
    switch (prioMode) {
        case PrioResolutionMode::FIXED_SCHED:
            return homaConfig->allPrio-1;
        case PrioResolutionMode::SIMULATED_SRBF: {
            uint32_t numPktsLeft =
                inbndMsg->bytesToGrant / maxSchedPktDataBytes; 
            return std::min((int)numPktsLeft,
                (int)homaConfig->prioResolverPrioLevels - 1);
        }
        case PrioResolutionMode::SMF_CBF_BASED:
            msgSize = inbndMsg->bytesToGrant;
            cutOffVec = &prioCutOffsFromCbf;
            break;
        case PrioResolutionMode::HEAD_TAIL_BYTES_FIRST_EQUAL_BYTES: {
            msgSize = msgSize - inbndMsg->totalUnschedBytes;
            uint32_t bytesTreatedUnsched = homaConfig->cbfCapMsgSize;
            if (msgSize > bytesTreatedUnsched &&
                    inbndMsg->bytesToGrant <= bytesTreatedUnsched) {
                msgSize = bytesTreatedUnsched;
            }
            cutOffVec = &prioCutOffsHeadTailFirst;
            break;
        }
        case PrioResolutionMode::HEAD_TAIL_BYTES_FIRST_EXP_BYTES: {
            msgSize = msgSize - inbndMsg->totalUnschedBytes;
            uint32_t bytesTreatedUnsched = homaConfig->cbfCapMsgSize;
            if (msgSize > bytesTreatedUnsched &&
                    inbndMsg->bytesToGrant <= bytesTreatedUnsched) {
                msgSize = bytesTreatedUnsched;
            }
            cutOffVec = &prioCutOffsHeadTailFirstExp;
            break;
        }
        case PrioResolutionMode::HEAD_TAIL_BYTES_FIRST_EQUAL_COUNTS: {
            msgSize = msgSize - inbndMsg->totalUnschedBytes;
            uint32_t bytesTreatedUnsched = homaConfig->cbfCapMsgSize;
            if (msgSize > bytesTreatedUnsched &&
                    inbndMsg->bytesToGrant <= bytesTreatedUnsched) {
                msgSize = bytesTreatedUnsched;
            }
            cutOffVec = &prioCutOffsFromCdf;
            break;
        }
        case PrioResolutionMode::HEAD_TAIL_BYTES_FIRST_EXP_COUNTS: {
            msgSize = msgSize - inbndMsg->totalUnschedBytes;
            uint32_t bytesTreatedUnsched = homaConfig->cbfCapMsgSize;
            if (msgSize > bytesTreatedUnsched &&
                    inbndMsg->bytesToGrant <= bytesTreatedUnsched) {
                msgSize = bytesTreatedUnsched;
            }
            cutOffVec = &prioCutOffsExpCdf;
            break;
        }
        case PrioResolutionMode::STATIC_FROM_CDF:
            cutOffVec = &prioCutOffsFromCdf;
            break;
        case PrioResolutionMode::STATIC_FROM_CBF:
            cutOffVec = &prioCutOffsFromCbf;
            break;
        case PrioResolutionMode::STATIC_EXP_CDF:
            cutOffVec = &prioCutOffsExpCdf;
            break;
        case PrioResolutionMode::STATIC_EXP_CBF:
            cutOffVec = &prioCutOffsExpCbf;
            break;
        default:
            throw cRuntimeError("Invalid priority mode: prioMode(%d) for"
                " scheduled packets", prioMode);
    }

    size_t mid, high, low;
    low = 0;
    high = cutOffVec->size() - 1;
    while(low < high) {
        mid = (high + low) / 2;
        if (msgSize <= cutOffVec->at(mid)) {
            high = mid;
        } else {
            low = mid + 1;
        }
    }
    return (uint16_t)high;
}

void
PriorityResolver::recomputeCbf(uint32_t cbfCapMsgSize)
{
    if (cbfCapMsgSize != lastCbfCapMsgSize) {
        distEstimator->getCbfFromCdf(distEstimator->cdfFromFile,
            cbfCapMsgSize);
        setCbfPrioCutOffs();
        setHeadTailFirstPrioCutOffs();
        setExpFromCbfPrioCutOffs();
        setExpHeadTailFirstPrioCutOffs();
        lastCbfCapMsgSize = cbfCapMsgSize;
    }
}

void
PriorityResolver::setCdfPrioCutOffs()
{
    prioCutOffsFromCdf.clear();
    ASSERT(cbf->size() == cdf->size() && cdf->at(cdf->size() - 1).second == 1.00
        && cbf->at(cbf->size() - 1).second == 1.00);
    double probMax = 1.0;
    double probStep = probMax / homaConfig->prioResolverPrioLevels;
    size_t i = 0;
    uint32_t prevCutOffCdfSize = UINT32_MAX;
    for (double prob = probStep; prob < probMax; prob += probStep) {
        for (; i < cdf->size(); i++) {
            if (cdf->at(i).first == prevCutOffCdfSize) {
                // Do not add duplicate sizes to cutOffSizes vector
                continue;
            }
            if (cdf->at(i).second >= prob) {
                prioCutOffsFromCdf.push_back(cdf->at(i).first);
                prevCutOffCdfSize = cdf->at(i).first;
                break;
            }
        }

    }
    prioCutOffsFromCdf.push_back(UINT32_MAX);
}

void
PriorityResolver::setExpFromCdfPrioCutOffs()
{
    prioCutOffsExpCdf.clear();
    ASSERT(cbf->size() == cdf->size() && cdf->at(cdf->size() - 1).second == 1.00
        && cbf->at(cbf->size() - 1).second == 1.00);
    double probMax = 1.0;
    double probStep =
        probMax / (2 - pow(2.0, 1-(int)(homaConfig->prioResolverPrioLevels)));
    size_t i = 0;
    uint32_t prevCutOffExpCdfSize = UINT32_MAX;
    for (double prob = probStep; prob < probMax; prob += probStep) {
        probStep /= 2.0;
        for (; i < cdf->size(); i++) {
            if (cdf->at(i).first == prevCutOffExpCdfSize) {
                // Do not add duplicate sizes to cutOffSizes vector
                continue;
            }
            if (cdf->at(i).second >= prob) {
                prioCutOffsExpCdf.push_back(cdf->at(i).first);
                prevCutOffExpCdfSize = cdf->at(i).first;
                break;
            }
        }
    }
    prioCutOffsExpCdf.push_back(UINT32_MAX);
}

void
PriorityResolver::setCbfPrioCutOffs()
{
    prioCutOffsFromCbf.clear();
    ASSERT(cbf->size() == cdf->size() && cdf->at(cdf->size() - 1).second == 1.00
        && cbf->at(cbf->size() - 1).second == 1.00);
    double probMax = 1.0;
    double probStep = probMax / homaConfig->prioResolverPrioLevels;
    size_t j = 0;
    uint32_t prevCutOffCbfSize = UINT32_MAX;
    for (double prob = probStep; prob < probMax; prob += probStep) {
        for (; j < cbf->size(); j++) {
            if (cbf->at(j).first == prevCutOffCbfSize) {
                // Do not add duplicate sizes to cutOffSizes vector
                continue;
            }
            if (cbf->at(j).second >= prob) {
                prioCutOffsFromCbf.push_back(cbf->at(j).first);
                prevCutOffCbfSize = cbf->at(j).first;
                break;
            }
        }
    }
    prioCutOffsFromCbf.push_back(UINT32_MAX);
}

void
PriorityResolver::setExpFromCbfPrioCutOffs()
{
    prioCutOffsExpCbf.clear();
    ASSERT(cbf->size() == cdf->size() && cdf->at(cdf->size() - 1).second == 1.00
        && cbf->at(cbf->size() - 1).second == 1.00);
    double probMax = 1.0;
    double probStep =
        probMax / (2 - pow(2.0, 1-(int)(homaConfig->prioResolverPrioLevels)));
    size_t i = 0;
    uint32_t prevCutOffExpCbfSize = UINT32_MAX;
    for (double prob = probStep; prob < probMax; prob += probStep) {
        probStep /= 2.0;
        for (; i < cbf->size(); i++) {
            if (cbf->at(i).first == prevCutOffExpCbfSize) {
                // Do not add duplicate sizes to cutOffSizes vector
                continue;
            }
            if (cbf->at(i).second >= prob) {
                prioCutOffsExpCbf.push_back(cbf->at(i).first);
                prevCutOffExpCbfSize = cbf->at(i).first;
                break;
            }
        }
    }
    prioCutOffsExpCbf.push_back(UINT32_MAX);
}

void
PriorityResolver::setHeadTailFirstPrioCutOffs()
{
    prioCutOffsHeadTailFirst.clear();
    ASSERT(cbfLastCapBytes->at(cbfLastCapBytes->size() - 1).second == 1.00);
    double probMax = 1.0;
    double probStep = probMax / homaConfig->prioResolverPrioLevels;
    size_t j = 0;
    uint32_t prevCutOffCbfSize = UINT32_MAX;
    for (double prob = probStep; prob < probMax; prob += probStep) {
        for (; j < cbfLastCapBytes->size(); j++) {
            if (cbfLastCapBytes->at(j).first == prevCutOffCbfSize) {
                // Do not add duplicate sizes to cutOffSizes vector
                continue;
            }
            if (cbfLastCapBytes->at(j).second >= prob) {
                prioCutOffsHeadTailFirst.push_back(cbfLastCapBytes->at(j).first);
                prevCutOffCbfSize = cbfLastCapBytes->at(j).first;
                break;
            }
        }
    }
    prioCutOffsHeadTailFirst.push_back(UINT32_MAX);
}

void
PriorityResolver::setExpHeadTailFirstPrioCutOffs()
{
    prioCutOffsHeadTailFirstExp.clear();
    ASSERT(cbfLastCapBytes->at(cbfLastCapBytes->size() - 1).second == 1.00);
    double probMax = 1.0;
    double probStep =
        probMax / (2 - pow(2.0, 1-(int)(homaConfig->prioResolverPrioLevels)));
    size_t j = 0;
    uint32_t prevCutOffExpCbfSize = UINT32_MAX;
    for (double prob = probStep; prob < probMax; prob += probStep) {
        probStep /= 2.0;
        for (; j < cbfLastCapBytes->size(); j++) {
            if (cbfLastCapBytes->at(j).first == prevCutOffExpCbfSize) {
                // Do not add duplicate sizes to cutOffSizes vector
                continue;
            }
            if (cbfLastCapBytes->at(j).second >= prob) {
                prioCutOffsHeadTailFirstExp.push_back(cbfLastCapBytes->at(j).first);
                prevCutOffExpCbfSize = cbfLastCapBytes->at(j).first;
                break;
            }
        }
    }
    prioCutOffsHeadTailFirstExp.push_back(UINT32_MAX);
}


PriorityResolver::PrioResolutionMode
PriorityResolver::strPrioModeToInt(const char* prioResMode)
{
    if (strcmp(prioResMode, "STATIC_FROM_CDF") == 0) {
        return PrioResolutionMode::STATIC_FROM_CDF;
    } else if (strcmp(prioResMode, "STATIC_FROM_CBF") == 0) {
        return PrioResolutionMode::STATIC_FROM_CBF;
    } else if (strcmp(prioResMode, "FIXED_UNSCHED") == 0) {
        return PrioResolutionMode::FIXED_UNSCHED;
    } else if (strcmp(prioResMode, "FIXED_SCHED") == 0) {
        return PrioResolutionMode::FIXED_SCHED;
    } else if (strcmp(prioResMode, "STATIC_EXP_CDF") == 0) {
        return PrioResolutionMode::STATIC_EXP_CDF;
    } else if (strcmp(prioResMode, "STATIC_EXP_CBF") == 0) {
        return PrioResolutionMode::STATIC_EXP_CBF;
    } else if (strcmp(prioResMode, "SIMULATED_SRBF") == 0) {
        return PrioResolutionMode::SIMULATED_SRBF;
    } else if (strcmp(prioResMode, "SMF_CBF_BASED") == 0) {
        return PrioResolutionMode::SMF_CBF_BASED;
    } else if (strcmp(prioResMode, "HEAD_TAIL_BYTES_FIRST_EQUAL_BYTES") == 0) {
        return PrioResolutionMode::HEAD_TAIL_BYTES_FIRST_EQUAL_BYTES;
    } else if (strcmp(prioResMode, "HEAD_TAIL_BYTES_FIRST_EXP_BYTES") == 0) {
        return PrioResolutionMode::HEAD_TAIL_BYTES_FIRST_EXP_BYTES;
    } else if (strcmp(prioResMode, "HEAD_TAIL_BYTES_FIRST_EQUAL_COUNTS") == 0) {
        return PrioResolutionMode::HEAD_TAIL_BYTES_FIRST_EQUAL_COUNTS;
    } else if (strcmp(prioResMode, "HEAD_TAIL_BYTES_FIRST_EXP_COUNTS") == 0) {
        return PrioResolutionMode::HEAD_TAIL_BYTES_FIRST_EXP_COUNTS;
    } else {
        return PrioResolutionMode::INVALID_PRIO_MODE;
    }
}

void
PriorityResolver::printCbfCdf(WorkloadEstimator::CdfVector* vec)
{
    for (auto& elem:*vec) {
        std::cout << elem.first << " : " << elem.second << std::endl;
    }
}